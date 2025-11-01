WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    -- compute length of stay in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.admission_location = 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  hospital_expire_flag,
  COUNT(*) AS n_patients,
  -- mean LOS
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- median LOS via approximate quantiles
  ROUND(APPROX_QUANTILES(los_days, 2)[OFFSET(1)], 2) AS median_los_days,
  -- percent with LOS <= 5 days
  ROUND(
    100.0 * SUM(IF(los_days <= 5, 1, 0)) / COUNT(*)
  , 2) AS pct_los_le_5_days
FROM
  cohort
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;