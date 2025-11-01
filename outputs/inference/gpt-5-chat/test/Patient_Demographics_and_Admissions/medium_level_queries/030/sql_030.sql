WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admission_type = 'ELECTIVE'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  CASE
    WHEN hospital_expire_flag = 0 THEN 'Discharged alive'
    WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
  END AS discharge_status,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(25)], 2) AS p25_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS p50_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days
FROM
  cohort
GROUP BY
  hospital_expire_flag
ORDER BY
  discharge_status;