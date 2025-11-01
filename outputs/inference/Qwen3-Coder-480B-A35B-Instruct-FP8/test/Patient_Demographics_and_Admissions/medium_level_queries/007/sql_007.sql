WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
    AND a.dischtime IS NOT NULL
),

los_stats AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_p50,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_p75,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS los_p90,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS los_p95
  FROM
    filtered_admissions
  GROUP BY
    hospital_expire_flag
),

percentile_ranks AS (
  SELECT
    hospital_expire_flag,
    los_days,
    PERCENT_RANK() OVER (PARTITION BY hospital_expire_flag ORDER BY los_days) AS percentile_rank
  FROM
    filtered_admissions
),

ten_day_percentile AS (
  SELECT
    hospital_expire_flag,
    MAX(CASE WHEN los_days <= 10 THEN percentile_rank ELSE 0 END) AS percentile_rank_10_days
  FROM
    percentile_ranks
  GROUP BY
    hospital_expire_flag
)

SELECT
  ls.hospital_expire_flag,
  ls.n_admissions,
  ls.los_p50,
  ls.los_p75,
  ls.los_p90,
  ls.los_p95,
  10 AS los_reference_days,
  td.percentile_rank_10_days
FROM
  los_stats ls
JOIN
  ten_day_percentile td
ON
  ls.hospital_expire_flag = td.hospital_expire_flag
ORDER BY
  ls.hospital_expire_flag;