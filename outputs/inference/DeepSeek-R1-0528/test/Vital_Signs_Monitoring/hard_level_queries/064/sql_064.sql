WITH cohort AS (
  SELECT 
    icu.subject_id, 
    icu.hadm_id, 
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  WHERE 
    p.gender = 'M'
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '584%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 45 AND 55
),

vitals AS (
  SELECT 
    c.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220052, 220181, 225312, 220045)  -- MAP & Heart Rate
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),

hourly_vitals AS (
  SELECT 
    stay_id,
    TIMESTAMP_TRUNC(charttime, HOUR) AS chart_hour,
    MAX(CASE 
        WHEN itemid IN (220052, 220181, 225312) AND valuenum < 65 THEN 1 
        ELSE 0 
    END) AS map_flag,
    MAX(CASE 
        WHEN itemid = 220045 AND valuenum > 100 THEN 1 
        ELSE 0 
    END) AS hr_flag
  FROM vitals
  GROUP BY stay_id, chart_hour
),

stay_aggregates AS (
  SELECT 
    stay_id,
    SUM(map_flag) AS count_map_low,
    SUM(hr_flag) AS count_hr_high,
    COUNT(DISTINCT chart_hour) AS total_hours
  FROM hourly_vitals
  GROUP BY stay_id
  HAVING COUNT(DISTINCT chart_hour) > 0  -- Exclude stays with no measurements
),

composite_score AS (
  SELECT 
    sa.stay_id,
    sa.count_map_low,
    sa.count_hr_high,
    (sa.count_map_low + sa.count_hr_high) AS instability_score
  FROM stay_aggregates sa
),

percentile AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100) AS percentiles
  FROM composite_score
),

percentile_value AS (
  SELECT 
    percentiles[OFFSET(95)] AS p95_score
  FROM percentile
),

quartiles AS (
  SELECT 
    cs.stay_id,
    cs.instability_score,
    NTILE(4) OVER (ORDER BY cs.instability_score) AS quartile
  FROM composite_score cs
),

cohort_outcomes AS (
  SELECT 
    q.stay_id,
    q.instability_score,
    q.quartile,
    CASE 
      WHEN q.quartile = 4 THEN 'Top Quartile' 
      ELSE 'Bottom Three Quartiles' 
    END AS group_label,
    c.icu_los,
    c.hospital_expire_flag,
    CASE WHEN sa.count_map_low > 0 THEN 1 ELSE 0 END AS hypotension_flag,
    CASE WHEN sa.count_hr_high > 0 THEN 1 ELSE 0 END AS tachycardia_flag
  FROM quartiles q
  INNER JOIN stay_aggregates sa ON q.stay_id = sa.stay_id
  INNER JOIN cohort c ON q.stay_id = c.stay_id
)

-- Final output: 95th percentile + group comparison
SELECT 
  '95th Percentile Composite Instability Score' AS metric,
  (SELECT p95_score FROM percentile_value) AS value,
  NULL AS group_label,
  NULL AS n,
  NULL AS hypotension_proportion,
  NULL AS tachycardia_proportion,
  NULL AS avg_icu_los,
  NULL AS mortality_rate
UNION ALL
SELECT 
  'Group Comparison' AS metric,
  NULL AS value,
  group_label,
  COUNT(stay_id) AS n,
  ROUND(AVG(hypotension_flag), 3) AS hypotension_proportion,
  ROUND(AVG(tachycardia_flag), 3) AS tachycardia_proportion,
  ROUND(AVG(icu_los), 3) AS avg_icu_los,
  ROUND(AVG(hospital_expire_flag), 3) AS mortality_rate
FROM cohort_outcomes
GROUP BY group_label;