WITH
-- Define mixed shock diagnosis codes (example - adjust as needed)
mixed_shock_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%shock%' AND LOWER(long_title) LIKE '%mixed%'
),

-- Get female patients aged 60-70 with mixed shock
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM s.intime) AS admission_year,
    p.anchor_age + (EXTRACT(YEAR FROM s.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` s ON a.hadm_id = s.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  JOIN mixed_shock_codes m ON d.icd_code = m.icd_code
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM s.intime) - p.anchor_year) BETWEEN 60 AND 70
),

-- Get vital signs in first 48 hours
vital_signs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    di.label,
    TIMESTAMP_DIFF(c.charttime, i.intime, HOUR) AS hours_since_admission
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
  JOIN cohort i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  WHERE
    c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
    AND (di.label LIKE '%MAP%' OR di.label LIKE '%Heart Rate%')
),

-- Calculate instability score components
instability_components AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    -- Example instability score calculation (adjust as needed)
    -- This is a placeholder - actual calculation would depend on clinical definition
    AVG(CASE WHEN label LIKE '%MAP%' AND valuenum < 65 THEN 1.0 ELSE 0.0 END) AS hypotension_score,
    AVG(CASE WHEN label LIKE '%Heart Rate%' AND valuenum > 100 THEN 1.0 ELSE 0.0 END) AS tachycardia_score,
    COUNT(DISTINCT CASE WHEN label LIKE '%MAP%' THEN itemid END) AS map_measurements,
    COUNT(DISTINCT CASE WHEN label LIKE '%Heart Rate%' THEN itemid END) AS hr_measurements
  FROM vital_signs
  GROUP BY subject_id, hadm_id, stay_id
),

-- Calculate final instability score (example - adjust as needed)
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    (hypotension_score + tachycardia_score) / 2 AS instability_score,
    hypotension_score,
    tachycardia_score,
    map_measurements,
    hr_measurements
  FROM instability_components
  WHERE map_measurements > 0 AND hr_measurements > 0  -- Ensure we have measurements
),

-- Get 95th percentile instability score
cohort_stats AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.95) OVER() AS p95_instability_score
  FROM instability_scores
  LIMIT 1
),

-- Rank patients by instability score
ranked_patients AS (
  SELECT
    i.*,
    c.los AS icu_los,
    c.hospital_expire_flag,
    c.age,
    PERCENT_RANK() OVER(ORDER BY i.instability_score) AS percentile_rank,
    cs.p95_instability_score
  FROM instability_scores i
  JOIN cohort c ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id AND i.stay_id = c.stay_id
  CROSS JOIN cohort_stats cs
),

-- Final comparison groups
comparison_groups AS (
  SELECT
    *,
    CASE WHEN percentile_rank >= 0.9 THEN 'Top Decile' ELSE 'Rest of Cohort' END AS comparison_group
  FROM ranked_patients
)

-- Final results
SELECT
  comparison_group,
  COUNT(*) AS patient_count,
  AVG(CASE WHEN hypotension_score > 0 THEN 1.0 ELSE 0.0 END) AS hypotension_prevalence,
  AVG(CASE WHEN tachycardia_score > 0 THEN 1.0 ELSE 0.0 END) AS tachycardia_prevalence,
  AVG(icu_los) AS avg_icu_los,
  AVG(CASE WHEN hospital_expire_flag THEN 1.0 ELSE 0.0 END) AS mortality_rate,
  AVG(instability_score) AS avg_instability_score,
  AVG(age) AS avg_age
FROM comparison_groups
GROUP BY comparison_group
ORDER BY comparison_group;