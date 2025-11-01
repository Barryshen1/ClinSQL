WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    s.curr_service,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.services` s
    ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND UPPER(a.admission_type) != 'ELECTIVE'
    AND UPPER(s.curr_service) LIKE 'MED%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) >= 0
)

SELECT
  CASE WHEN hospital_expire_flag = 1 THEN 'In-hospital death' ELSE 'Discharged alive' END AS discharge_status,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days,
  ROUND(100 * SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percentile_rank_5day_stay
FROM
  cohort
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag DESC;