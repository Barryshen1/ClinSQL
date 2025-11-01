WITH cohort AS (
  SELECT
    a.hospital_expire_flag AS outcome,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type != 'EMERGENCY'
    AND a.hospital_expire_flag IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
percentiles AS (
  SELECT
    CASE
      WHEN outcome = 0 THEN 'alive'
      WHEN outcome = 1 THEN 'death'
    END AS outcome,
    APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(50)] AS p50,
    APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(75)] AS p75,
    APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(90)] AS p90,
    APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(95)] AS p95,
    NULL AS pct_rank_7
  FROM
    cohort
  GROUP BY
    outcome
),
overall_percentile_rank AS (
  SELECT
    'overall' AS outcome,
    NULL AS p50,
    NULL AS p75,
    NULL AS p90,
    NULL AS p95,
    (COUNTIF(los_days <= 7) * 100.0 / COUNT(*)) AS pct_rank_7
  FROM
    cohort
)
SELECT
  outcome,
  p50,
  p75,
  p90,
  p95,
  pct_rank_7
FROM
  percentiles
UNION ALL
SELECT
  outcome,
  p50,
  p75,
  p90,
  p95,
  pct_rank_7
FROM
  overall_percentile_rank;