WITH sub AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admission_type = 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'died'
    ELSE 'alive'
  END AS discharge_status,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS count_los_ge_7,
  SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS count_los_ge_14,
  SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS prop_los_ge_7,
  SAFE_DIVIDE(SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END), COUNT(*)) AS prop_los_ge_14,
  -- Percentile rank for 10-day LOS is the proportion with LOS <= 10
  SAFE_DIVIDE(SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END), COUNT(*)) AS percentile_rank_10
FROM
  sub
GROUP BY
  discharge_status
ORDER BY
  discharge_status;