WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    CASE WHEN a.hospital_expire_flag = 1 THEN 'died' ELSE 'survived' END AS outcome,
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    -- admission_location indicating transfer from another hospital (case-insensitive match)
    AND a.admission_location IS NOT NULL
    AND LOWER(a.admission_location) LIKE '%transfer%'
    -- require valid times to compute LOS
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- ensure non-negative LOS
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
)
SELECT
  outcome,
  COUNT(*) AS admissions_count,
  -- APPROX_QUANTILES returns an array of length (num_buckets + 1); use offsets for percentiles
  -- p50:
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los_days,
  -- p75:
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
  -- p90:
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los_days,
  -- p95:
  APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95_los_days,
  -- percentile rank of a 10-day LOS (percentage of admissions with LOS <= 10 days)
  100.0 * SUM(IF(los_days <= 10.0, 1, 0)) / COUNT(*) AS pct_rank_of_10d
FROM
  cohort
GROUP BY
  outcome
ORDER BY
  outcome DESC;