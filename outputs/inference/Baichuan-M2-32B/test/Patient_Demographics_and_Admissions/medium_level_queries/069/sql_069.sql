WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type = 'EMERGENCY'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL  -- Ensure admittime is not null to avoid null los_days
),
proportion AS (
  SELECT 
    hospital_expire_flag,
    COUNT(CASE WHEN los_days >= 7 THEN 1 END) * 1.0 / NULLIF(COUNT(*), 0) AS proportion_ge7
  FROM cohort
  GROUP BY hospital_expire_flag
),
percentile_rank AS (
  SELECT 
    (SELECT COUNT(*) FROM cohort WHERE los_days <= 7) * 1.0 / 
    NULLIF((SELECT COUNT(*) FROM cohort), 0) AS pct_rank_7
)
SELECT 
  'alive' AS discharge_status,
  proportion_ge7,
  NULL AS pct_rank_7
FROM proportion
WHERE hospital_expire_flag = 0
UNION ALL
SELECT 
  'died' AS discharge_status,
  proportion_ge7,
  NULL AS pct_rank_7
FROM proportion
WHERE hospital_expire_flag = 1
UNION ALL
SELECT 
  'percentile_rank_7' AS discharge_status,
  NULL,
  (SELECT pct_rank_7 FROM percentile_rank);