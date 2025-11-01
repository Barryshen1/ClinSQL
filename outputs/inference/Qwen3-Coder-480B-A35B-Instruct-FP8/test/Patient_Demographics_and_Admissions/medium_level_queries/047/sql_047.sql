WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type = 'TRANSFER'
    AND a.dischtime IS NOT NULL
    AND (
      a.discharge_location IN ('HOME', 'FACILITY')
      OR a.hospital_expire_flag = 1
    )
),
los_stats AS (
  SELECT
    los_days,
    AVG(los_days) OVER() AS mean_los,
    STDDEV(los_days) OVER() AS stddev_los,
    PERCENT_RANK() OVER (ORDER BY los_days) AS percentile_rank
  FROM
    filtered_admissions
)
SELECT
  AVG(mean_los) AS mean_los,
  AVG(stddev_los) AS stddev_los,
  MAX(CASE WHEN los_days = 5 THEN percentile_rank END) AS percentile_rank_5_days
FROM
  los_stats
LIMIT 1;