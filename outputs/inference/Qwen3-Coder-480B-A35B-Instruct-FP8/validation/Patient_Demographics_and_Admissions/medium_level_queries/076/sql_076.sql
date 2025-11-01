WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 3600) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

stats AS (
  SELECT
    hospital_expire_flag,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los
  FROM
    cohort
  GROUP BY
    hospital_expire_flag
),

percentile_ranks AS (
  SELECT
    hospital_expire_flag,
    los_days,
    PERCENT_RANK() OVER (PARTITION BY hospital_expire_flag ORDER BY los_days) AS percentile_rank
  FROM
    cohort
),

five_day_rank AS (
  SELECT
    hospital_expire_flag,
    MAX(CASE WHEN los_days <= 5 THEN percentile_rank END) AS percentile_rank_5_days
  FROM
    percentile_ranks
  GROUP BY
    hospital_expire_flag
)

SELECT
  s.hospital_expire_flag,
  s.mean_los,
  s.median_los,
  s.p75_los,
  s.p90_los,
  COALESCE(f.percentile_rank_5_days, 0) AS percentile_rank_5day_los
FROM
  stats s
LEFT JOIN
  five_day_rank f
ON
  s.hospital_expire_flag = f.hospital_expire_flag
ORDER BY
  s.hospital_expire_flag;