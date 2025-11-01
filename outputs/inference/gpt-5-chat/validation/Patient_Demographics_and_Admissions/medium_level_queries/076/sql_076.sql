WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
-- Aggregate LOS stats by alive vs in-hospital death
, stats_by_outcome AS (
  SELECT
    hospital_expire_flag,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los
  FROM cohort
  GROUP BY hospital_expire_flag
)
-- Overall percentile rank for 5-day LOS in the cohort
, percentile_5day AS (
  SELECT
    100.0 * SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_rank_5d
  FROM cohort
)
SELECT
  s.hospital_expire_flag,
  s.mean_los,
  s.p50_los,
  s.p75_los,
  s.p90_los,
  p.percentile_rank_5d
FROM stats_by_outcome s
CROSS JOIN percentile_5day p
ORDER BY hospital_expire_flag;