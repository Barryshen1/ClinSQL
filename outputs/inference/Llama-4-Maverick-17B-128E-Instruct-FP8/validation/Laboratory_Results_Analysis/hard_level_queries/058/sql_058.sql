WITH 
-- Step 1: Identify ACS patients and include necessary timestamps
acs_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 40 AND 50
    AND d.icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Acute coronary syndrome%')
),

-- Step 2: Calculate laboratory instability score within first 48 hours
lab_instability AS (
  SELECT a.subject_id, a.hadm_id,
         SUM(CASE WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1 ELSE 0 END) AS instability_score
  FROM acs_patients a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
  WHERE l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY a.subject_id, a.hadm_id
),

-- Step 3: Find 90th percentile of instability score
percentile_threshold AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS threshold
  FROM lab_instability
),

-- Step 4: Compare outcomes for patients above and below threshold
outcomes AS (
  SELECT 
    a.hadm_id,
    l.instability_score,
    CASE WHEN l.instability_score >= (SELECT threshold FROM percentile_threshold) THEN 'Above Threshold' ELSE 'Below Threshold' END AS threshold_group,
    a.hospital_expire_flag AS mortality,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM acs_patients a
  INNER JOIN lab_instability l ON a.hadm_id = l.hadm_id
)

-- Final output
SELECT 
  threshold_group,
  COUNT(*) AS num_patients,
  AVG(mortality) AS mortality_rate,
  AVG(los) AS mean_los
FROM outcomes
GROUP BY threshold_group

UNION ALL

-- General inpatient population for comparison (simplified)
SELECT 
  'General Population' AS threshold_group,
  COUNT(*) AS num_patients,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions`;