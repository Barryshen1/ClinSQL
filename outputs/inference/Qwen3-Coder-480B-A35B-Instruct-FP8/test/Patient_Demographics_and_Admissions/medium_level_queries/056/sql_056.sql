WITH cohort AS (
  SELECT
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    PERCENT_RANK() OVER (PARTITION BY a.hospital_expire_flag ORDER BY DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS los_percentile_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.admittime < a.dischtime
),
stats AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge_7,
    SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS los_ge_14
  FROM
    cohort
  GROUP BY
    hospital_expire_flag
),
percentile_ranks AS (
  SELECT
    hospital_expire_flag,
    APPROX_TOP_COUNT(los_percentile_rank, 1)[OFFSET(0)].value AS percentile_rank_10_day_los
  FROM
    cohort
  WHERE
    los_days = 10
  GROUP BY
    hospital_expire_flag
)
SELECT
  s.hospital_expire_flag,
  s.total_patients,
  s.los_ge_7 AS count_los_ge_7,
  s.los_ge_14 AS count_los_ge_14,
  ROUND(s.los_ge_7 / s.total_patients, 4) AS prop_los_ge_7,
  ROUND(s.los_ge_14 / s.total_patients, 4) AS prop_los_ge_14,
  pr.percentile_rank_10_day_los
FROM
  stats s
LEFT JOIN
  percentile_ranks pr
ON
  s.hospital_expire_flag = pr.hospital_expire_flag
ORDER BY
  s.hospital_expire_flag;