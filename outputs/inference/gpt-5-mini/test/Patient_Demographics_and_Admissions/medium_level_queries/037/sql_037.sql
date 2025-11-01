WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admission_type IS NOT NULL
    AND UPPER(a.admission_type) != 'EMERGENCY'
)

SELECT
  CASE WHEN hospital_expire_flag = 1 THEN 'In-hospital death' ELSE 'Discharged alive' END AS outcome,
  COUNT(*) AS n_admissions,
  ROUND((APPROX_QUANTILES(los_days, 100))[OFFSET(50)], 2) AS p50_days,
  ROUND((APPROX_QUANTILES(los_days, 100))[OFFSET(75)], 2) AS p75_days,
  ROUND((APPROX_QUANTILES(los_days, 100))[OFFSET(90)], 2) AS p90_days,
  ROUND((APPROX_QUANTILES(los_days, 100))[OFFSET(95)], 2) AS p95_days,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_le_7_days
FROM cohort
GROUP BY hospital_expire_flag
ORDER BY hospital_expire_flag DESC;