WITH cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_location LIKE 'TRANSFER FROM HOSP%'
    AND CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) BETWEEN 78 AND 88
    AND a.dischtime IS NOT NULL
),
overall_percentile AS (
  SELECT
    SAFE_DIVIDE(COUNTIF(los_days <= 10), COUNT(*)) * 100 AS pct_10day
  FROM
    cohort
)
SELECT
  CASE WHEN c.hospital_expire_flag = 0 THEN 'Survived' ELSE 'Died' END AS outcome,
  COUNT(*) AS num_admissions,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95_days,
  o.pct_10day AS overall_pct_rank_10day_los
FROM
  cohort c
CROSS JOIN
  overall_percentile o
GROUP BY
  c.hospital_expire_flag, o.pct_10day
ORDER BY
  outcome;