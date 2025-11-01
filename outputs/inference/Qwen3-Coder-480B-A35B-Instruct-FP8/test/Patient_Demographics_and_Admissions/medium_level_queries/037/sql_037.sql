WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type != 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

los_percentiles AS (
  SELECT
    hospital_expire_flag,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95
  FROM
    filtered_admissions
  GROUP BY
    hospital_expire_flag
),

rank_7_days AS (
  SELECT
    hospital_expire_flag,
    los_days,
    PERCENT_RANK() OVER (PARTITION BY hospital_expire_flag ORDER BY los_days) AS percentile_rank
  FROM
    filtered_admissions
  WHERE
    los_days = 7
)

SELECT
  lp.hospital_expire_flag,
  lp.p50,
  lp.p75,
  lp.p90,
  lp.p95,
  COALESCE(r7.percentile_rank, 0) AS percentile_rank_7_days
FROM
  los_percentiles lp
LEFT JOIN
  rank_7_days r7
ON
  lp.hospital_expire_flag = r7.hospital_expire_flag
ORDER BY
  lp.hospital_expire_flag;