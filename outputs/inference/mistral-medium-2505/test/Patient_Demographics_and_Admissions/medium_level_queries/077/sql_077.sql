WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR)/24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND a.dischtime IS NOT NULL
    AND a.admittime < a.dischtime
)

SELECT
  CASE
    WHEN hospital_expire_flag = 0 THEN 'Discharged Alive'
    WHEN hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
  END AS discharge_status,
  COUNT(*) AS admission_count,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
  ROUND(100 * SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_5day_or_less_los
FROM
  filtered_admissions
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;