WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type = 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),
los_stats AS (
  SELECT
    *,
    los_days >= 7 AS los_ge_7,
    PERCENT_RANK() OVER (ORDER BY los_days) AS los_percentile_rank
  FROM
    cohort
)
SELECT
  -- Proportion with LOS ≥7 by mortality status
  AVG(CASE WHEN hospital_expire_flag = 0 AND los_ge_7 THEN 1 ELSE 0 END) AS prop_los_ge_7_alive,
  AVG(CASE WHEN hospital_expire_flag = 1 AND los_ge_7 THEN 1 ELSE 0 END) AS prop_los_ge_7_expired,

  -- Percentile rank of 7-day LOS in this cohort
  MAX(CASE WHEN los_days = 7 THEN los_percentile_rank END) AS percentile_rank_7_days
FROM
  los_stats;