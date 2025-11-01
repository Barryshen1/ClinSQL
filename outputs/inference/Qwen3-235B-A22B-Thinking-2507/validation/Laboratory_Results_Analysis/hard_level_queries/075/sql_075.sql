WITH 
-- Step 1: Define DVT ICD-10 codes
dvt_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
    AND icd_code IN (
      'I80.2', 'I80.3', 'I80.8', 'I80.9', 
      'I82.0', 'I82.1', 'I82.2', 'I82.3', 'I82.4', 'I82.5', 'I82.6', 'I82.7', 'I82.8', 'I82.9'
    )
),
-- Step 2: Cohort of admissions (male, age 42-52, with DVT)
cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    -- Compute age at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 42 AND 52
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_version = 10
        AND icd_code IN (SELECT icd_code FROM dvt_codes)
    )
),
-- Step 3: For each admission in cohort, count critical lab events in first 72h
lab_instability AS (
  SELECT 
    c.hadm_id,
    COUNT(*) AS instability_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  WHERE l.charttime >= c.admittime
    AND l.charttime <= c.admittime + INTERVAL '72' HOUR
    AND l.flag IN ('critical', 'critical high', 'critical low')
  GROUP BY c.hadm_id
),
-- Step 4: Get instability scores for all cohort members (including 0 for those with no critical labs)
instability_scores AS (
  SELECT 
    c.hadm_id,
    COALESCE(li.instability_score, 0) AS instability_score
  FROM cohort c
  LEFT JOIN lab_instability li
    ON c.hadm_id = li.hadm_id
),
-- Step 5: Calculate 95th percentile of instability scores (FIXED: BigQuery-compatible percentile)
percentile AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95
  FROM instability_scores
),
-- Step 6: Get statistics for high instability group (>= 95th percentile)
high_group AS (
  SELECT 
    c.hadm_id,
    c.hospital_expire_flag,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND) / (24*60*60) AS los_days,
    iscore.instability_score
  FROM cohort c
  INNER JOIN instability_scores iscore
    ON c.hadm_id = iscore.hadm_id
  CROSS JOIN percentile p
  WHERE iscore.instability_score >= p.p95
),
high_group_stats AS (
  SELECT 
    AVG(hospital_expire_flag) AS mortality_high,
    AVG(los_days) AS mean_los_high,
    AVG(instability_score) AS critical_lab_rate_high
  FROM high_group
),
-- Step 7: Calculate average critical lab rate for all inpatients
all_inpatients AS (
  SELECT 
    a.hadm_id,
    COUNT(l.hadm_id) AS critical_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
    AND l.charttime >= a.admittime
    AND l.charttime <= a.admittime + INTERVAL '72' HOUR
    AND l.flag IN ('critical', 'critical high', 'critical low')
  GROUP BY a.hadm_id
),
all_inpatients_avg AS (
  SELECT AVG(critical_count) AS critical_lab_rate_all
  FROM all_inpatients
)
-- Final result
SELECT 
  p.p95 AS percentile_95,
  h.mortality_high,
  h.mean_los_high,
  h.critical_lab_rate_high,
  a.critical_lab_rate_all
FROM percentile p
CROSS JOIN high_group_stats h
CROSS JOIN all_inpatients_avg a;