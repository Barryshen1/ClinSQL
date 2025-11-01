WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.deathtime,
    a.hospital_expire_flag,
    -- Count distinct diagnoses as risk score proxy
    COUNT(DISTINCT d.icd_code) AS num_diagnoses,
    -- Check for major complications: pneumonia (J18%), sepsis (A41%), severe sepsis (R65.2), DVT (I82%), PE (I26%)
    MAX(CASE WHEN (d.icd_code LIKE 'J18%' OR d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R65.2%' OR d.icd_code LIKE 'I82%' OR d.icd_code LIKE 'I26%') AND d.icd_version = 10 THEN 1 ELSE 0 END) AS has_complication
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND d.icd_code LIKE 'I61%'  -- ICH ICD-10 codes
    AND d.icd_version = 10       -- Ensure ICD-10
  GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
),

cohort_with_quintile AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY num_diagnoses) AS quintile
  FROM cohort
),

-- Calculate LOS for survivors only
survivor_los AS (
  SELECT 
    quintile,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM cohort_with_quintile
  WHERE hospital_expire_flag = 0
)

SELECT 
  q.quintile,
  COUNT(*) AS n,
  -- 30-day mortality: died within 30 days of admission
  ROUND(100 * AVG(CASE WHEN deathtime IS NOT NULL AND DATETIME_DIFF(deathtime, admittime, DAY) <= 30 THEN 1 ELSE 0 END), 2) AS mortality_30d_percent,
  -- Major complication percentage
  ROUND(100 * AVG(has_complication), 2) AS complication_percent,
  -- Median LOS for survivors
  ROUND(PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY quintile), 2) AS median_survivor_los
FROM cohort_with_quintile q
LEFT JOIN survivor_los s ON q.quintile = s.quintile
GROUP BY q.quintile
ORDER BY q.quintile;