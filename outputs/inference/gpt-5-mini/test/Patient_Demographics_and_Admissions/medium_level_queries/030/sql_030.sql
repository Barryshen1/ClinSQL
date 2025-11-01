WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    -- female patients aged 44-54 (inclusive)
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    -- elective admissions only
    AND UPPER(a.admission_type) = 'ELECTIVE'
    -- require valid times and non-negative LOS
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
)

SELECT
  CASE WHEN hospital_expire_flag = 1 THEN 'died_in_hospital' ELSE 'discharged_alive' END AS discharge_status,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(quantiles[OFFSET(25)], 2) AS p25_los_days,
  ROUND(quantiles[OFFSET(50)], 2) AS p50_los_days,
  ROUND(quantiles[OFFSET(75)], 2) AS p75_los_days,
  ROUND(quantiles[OFFSET(90)], 2) AS p90_los_days
FROM (
  SELECT
    hospital_expire_flag,
    los_days,
    APPROX_QUANTILES(los_days, 100) AS quantiles
  FROM cohort
  GROUP BY hospital_expire_flag, los_days
)
GROUP BY hospital_expire_flag, quantiles
ORDER BY hospital_expire_flag DESC;