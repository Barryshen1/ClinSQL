WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_type <> 'ELECTIVE'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),
latest_service AS (
  SELECT
    s.hadm_id,
    s.curr_service,
    ROW_NUMBER() OVER (PARTITION BY s.hadm_id ORDER BY s.transfertime DESC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.services` s
),
filtered_cohort AS (
  SELECT
    c.*,
    ls.curr_service
  FROM
    cohort c
  JOIN
    latest_service ls
  ON
    c.hadm_id = ls.hadm_id
  WHERE
    ls.rn = 1
    AND ls.curr_service = 'MED'
),
stats AS (
  SELECT
    hospital_expire_flag,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los
  FROM
    filtered_cohort
  GROUP BY
    hospital_expire_flag
),
percentile_rank_5day AS (
  SELECT
    hospital_expire_flag,
    PERCENT_RANK() OVER (PARTITION BY hospital_expire_flag ORDER BY los_days) AS percentile_rank_5day
  FROM
    filtered_cohort
  WHERE
    los_days <= 5
)
SELECT
  s.*,
  MAX(CASE WHEN p.hospital_expire_flag = 0 THEN p.percentile_rank_5day END) AS percentile_rank_5day_alive,
  MAX(CASE WHEN p.hospital_expire_flag = 1 THEN p.percentile_rank_5day END) AS percentile_rank_5day_death
FROM
  stats s
LEFT JOIN
  percentile_rank_5day p
ON
  s.hospital_expire_flag = p.hospital_expire_flag
GROUP BY
  s.hospital_expire_flag,
  s.mean_los,
  s.median_los,
  s.p75_los,
  s.p90_los
ORDER BY
  s.hospital_expire_flag;