WITH patient_data AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
),
los_stats AS (
  SELECT 
    hospital_expire_flag,
    COUNT(hadm_id) AS num_admissions,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95_los
  FROM 
    patient_data
  GROUP BY 
    hospital_expire_flag
),
percentile_rank_10day AS (
  SELECT 
    hospital_expire_flag,
    COUNTIF(los_days <= 10) / COUNT(hadm_id) AS percentile_rank_10day
  FROM 
    patient_data
  GROUP BY 
    hospital_expire_flag
)
SELECT 
  ls.hospital_expire_flag,
  ls.num_admissions,
  ls.p50_los,
  ls.p75_los,
  ls.p90_los,
  ls.p95_los,
  pr.percentile_rank_10day
FROM 
  los_stats ls
INNER JOIN 
  percentile_rank_10day pr ON ls.hospital_expire_flag = pr.hospital_expire_flag
ORDER BY 
  ls.hospital_expire_flag;