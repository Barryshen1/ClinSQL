WITH cohort AS (
  -- Base cohort: males, age 63-73, post-op, with ICU stay (first stay per admission)
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.los AS icu_los,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id, a.hadm_id ORDER BY i.intime) AS rn_stay
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.admission_type IN ('SURGERY', 'SCHEDULED SURG')
    AND a.admission_location LIKE '%OPERATING ROOM%'
    AND i.first_careunit != 'Discharge'
),
first_stay AS (
  SELECT * FROM cohort WHERE rn_stay = 1
),
vitals AS (
  -- Extract relevant vitals in first 24h of ICU
  SELECT 
    fs.subject_id,
    fs.stay_id,
    fs.intime,
    ce.itemid,
    ce.charttime,
    ce.valuenum,
    -- Hourly bucket for episodes
    TIMESTAMP_TRUNC(ce.charttime, HOUR) AS hour_bucket
  FROM first_stay fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.subject_id = ce.subject_id 
    AND fs.hadm_id = ce.hadm_id 
    AND fs.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN fs.intime AND TIMESTAMP_ADD(fs.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (
      676,  -- Temp C
      220277, 220339,  -- SpO2
      618, 220210  -- RR
    )
),
episodes AS (
  -- Aggregate episodes per hour per patient
  SELECT 
    v.subject_id,
    v.itemid,
    v.hour_bucket,
    MIN(v.valuenum) AS min_val  -- Use min per hour to detect any episode
  FROM vitals v
  GROUP BY v.subject_id, v.itemid, v.hour_bucket
),
patient_scores AS (
  -- Compute instability score and episode flags per patient
  SELECT 
    fs.subject_id,
    fs.anchor_age,
    fs.hadm_id,
    fs.intime,
    fs.icu_los,
    fs.hospital_expire_flag,
    -- Fever episodes (>38.5 C)
    COUNTIF(e.itemid IN (676) AND e.min_val > 38.5) AS fever_episodes,
    -- SpO2 <90%
    COUNTIF(e.itemid IN (220277, 220339) AND e.min_val < 90) AS spo2_low_episodes,
    -- RR >20
    COUNTIF(e.itemid IN (618, 220210) AND e.min_val > 20) AS rr_high_episodes,
    -- Instability score
    (COUNTIF(e.itemid IN (676) AND e.min_val > 38.5) * 2  -- Fever weighted x2
     + COUNTIF(e.itemid IN (220277, 220339) AND e.min_val < 90)
     + COUNTIF(e.itemid IN (618, 220210) AND e.min_val > 20)) AS instability_score
  FROM first_stay fs
  LEFT JOIN episodes e ON fs.subject_id = e.subject_id
  GROUP BY fs.subject_id, fs.anchor_age, fs.hadm_id, fs.intime, fs.icu_los, fs.hospital_expire_flag
),
quartiles AS (
  -- Compute quartiles for all post-op cohort
  SELECT 
    APPROX_QUANTILES(instability_score, 4) OVER() AS q_scores,
    *
  FROM patient_scores
),
top_quartile_def AS (
  -- Define top quartile threshold (75th percentile)
  SELECT 
    q.scores[OFFSET(3)] AS q75_score
  FROM (
    SELECT APPROX_QUANTILES(instability_score, 4) AS scores
    FROM patient_scores
  ) q
),
subgroups AS (
  -- Assign subgroups: top vs non-top (within post-op cohort); all post-op for broader comparison
  SELECT 
    ps.*,
    CASE WHEN ps.instability_score >= tqd.q75_score THEN 'top_quartile' ELSE 'non_top_postop' END AS subgroup,
    'postop_cohort' AS comparison_group
  FROM patient_scores ps
  CROSS JOIN top_quartile_def tqd
  UNION ALL
  -- Broader comparison: all other post-op (non-top, but already included; for clarity, no need for extra)
  SELECT * FROM (
    SELECT 
      ps.*,
      'other_postop' AS subgroup,
      'all_postop' AS comparison_group
    FROM patient_scores ps
    CROSS JOIN top_quartile_def tqd
    WHERE ps.instability_score < tqd.q75_score
  )
),
metrics AS (
  -- Compute metrics by subgroup
  SELECT 
    subgroup,
    -- 95th percentile instability (only for top_quartile)
    MAX(CASE WHEN subgroup = 'top_quartile' THEN instability_score END) AS max_score_for_95th,  -- Approx via max for demo; use APPROX_QUANTILES in prod
    AVG(CASE WHEN fever_episodes > 0 THEN 1.0 ELSE 0 END) AS fever_rate,
    AVG(CASE WHEN spo2_low_episodes > 0 THEN 1.0 ELSE 0 END) AS spo2_rate,
    AVG(CASE WHEN rr_high_episodes > 0 THEN 1.0 ELSE 0 END) AS rr_rate,
    AVG(icu_los) AS avg_icu_los,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) AS mortality_rate,
    COUNT(*) AS n_patients
  FROM subgroups
  WHERE subgroup IN ('top_quartile', 'non_top_postop', 'other_postop')
  GROUP BY subgroup
),
final_95th AS (
  -- 95th percentile for top quartile
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_instability_top
  FROM subgroups 
  WHERE subgroup = 'top_quartile'
)
-- Output: 95th percentile + comparison table
SELECT 
  'p95_instability_top_quartile' AS metric,
  CAST(f.p95_instability_top AS STRING) AS top_quartile_value,
  NULL AS non_top_value,
  NULL AS other_postop_value
FROM final_95th f
UNION ALL
SELECT 
  metric,
  CAST(top_quartile_value AS STRING),
  CAST(non_top_value AS STRING),
  CAST(other_postop_value AS STRING)
FROM (
  SELECT 
    'fever_rate' AS metric,
    m1.fever_rate AS top_quartile_value,
    m2.fever_rate AS non_top_value,
    m3.fever_rate AS other_postop_value
  FROM metrics m1 
    LEFT JOIN metrics m2 ON m2.subgroup = 'non_top_postop'
    LEFT JOIN metrics m3 ON m3.subgroup = 'other_postop'
  WHERE m1.subgroup = 'top_quartile'
  UNION ALL
  SELECT 'spo2_rate' AS metric,
    m1.spo2_rate, m2.spo2_rate, m3.spo2_rate
  FROM metrics m1 LEFT JOIN metrics m2 ON m2.subgroup = 'non_top_postop'
    LEFT JOIN metrics m3 ON m3.subgroup = 'other_postop'
  WHERE m1.subgroup = 'top_quartile'
  UNION ALL
  SELECT 'rr_rate' AS metric,
    m1.rr_rate, m2.rr_rate, m3.rr_rate
  FROM metrics m1 LEFT JOIN metrics m2 ON m2.subgroup = 'non_top_postop'
    LEFT JOIN metrics m3 ON m3.subgroup = 'other_postop'
  WHERE m1.subgroup = 'top_quartile'
  UNION ALL
  SELECT 'avg_icu_los' AS metric,
    m1.avg_icu_los, m2.avg_icu_los, m3.avg_icu_los
  FROM metrics m1 LEFT JOIN metrics m2 ON m2.subgroup = 'non_top_postop'
    LEFT JOIN metrics m3 ON m3.subgroup = 'other_postop'
  WHERE m1.subgroup = 'top_quartile'
  UNION ALL
  SELECT 'mortality_rate' AS metric,
    m1.mortality_rate, m2.mortality_rate, m3.mortality_rate
  FROM metrics m1 LEFT JOIN metrics m2 ON m2.subgroup = 'non_top_postop'
    LEFT JOIN metrics m3 ON m3.subgroup = 'other_postop'
  WHERE m1.subgroup = 'top_quartile'
)
ORDER BY metric;