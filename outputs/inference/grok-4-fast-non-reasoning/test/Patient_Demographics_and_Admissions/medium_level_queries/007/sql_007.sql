WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    SAFE.DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admission_location = '***'
)
SELECT 
  hospital_expire_flag,
  COUNT(hadm_id) AS num_admissions,
  PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY hospital_expire_flag) AS los_p50,
  PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY hospital_expire_flag) AS los_p75,
  PERCENTILE_CONT(los_days, 0.9) OVER (PARTITION BY hospital_expire_flag) AS los_p90,
  PERCENTILE_CONT(los_days, 0.95) OVER (PARTITION BY hospital_expire_flag) AS los_p95,
  SAFE_DIVIDE(COUNTIF(los_days >= 10), COUNT(*)) * 100 AS pct_los_ge_10_days
FROM 
  filtered_admissions
GROUP BY 
  hospital_expire_flag
ORDER BY 
  hospital_expire_flag;