WITH services_first AS (
  SELECT 
    hadm_id, 
    curr_service,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.services`
),
cohort AS (
  SELECT 
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN services_first s 
    ON a.hadm_id = s.hadm_id AND s.rn = 1
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type = 'EMERGENCY'
    AND a.dischtime IS NOT NULL
    AND s.curr_service NOT LIKE '%SURG%'
),
alive_stats AS (
  SELECT 
    'Discharged Alive' AS category,
    COUNT(*) AS total,
    COUNTIF(los_days >= 7) AS num_los_ge7,
    ROUND(SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(*)) * 100, 2) AS proportion_ge7_pct
  FROM cohort 
  WHERE hospital_expire_flag = 0
),
died_stats AS (
  SELECT 
    'In-Hospital Mortality' AS category,
    COUNT(*) AS total,
    COUNTIF(los_days >= 7) AS num_los_ge7,
    ROUND(SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(*)) * 100, 2) AS proportion_ge7_pct
  FROM cohort 
  WHERE hospital_expire_flag = 1
),
overall_percentile AS (
  SELECT 
    'Percentile Rank of 7-Day LOS (Overall)' AS category,
    COUNT(*) AS total,
    NULL AS num_los_ge7,
    ROUND(SAFE_DIVIDE(COUNTIF(los_days < 7), COUNT(*)) * 100, 2) AS percentile_rank_pct
  FROM cohort
)
SELECT * FROM alive_stats
UNION ALL
SELECT * FROM died_stats
UNION ALL
SELECT * FROM overall_percentile
ORDER BY CASE 
  WHEN category = 'Discharged Alive' THEN 1 
  WHEN category = 'In-Hospital Mortality' THEN 2 
  ELSE 3 
END;