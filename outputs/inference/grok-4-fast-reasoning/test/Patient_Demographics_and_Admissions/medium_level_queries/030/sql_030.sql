WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    a.admission_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admission_type = 'ELECTIVE'
    AND a.dischtime IS NOT NULL
)
SELECT 
  hospital_expire_flag,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(24)] AS p25_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(49)] AS p50_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(74)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(89)] AS p90_los_days
FROM 
  cohort
GROUP BY 
  hospital_expire_flag
ORDER BY 
  hospital_expire_flag;