WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR)/24 AS los_days,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    a.admission_type != 'EMERGENCY'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.dischtime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR)/24 > 0
),

los_stats AS (
  SELECT
    hospital_expire_flag,
    CASE WHEN hospital_expire_flag = 0 THEN 'Alive' ELSE 'In-Hospital Death' END AS discharge_status,
    COUNT(*) AS admission_count,
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p50,
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS p75,
    APPROX_QUANTILES(los_days, 10)[OFFSET(8)] AS p90,
    APPROX_QUANTILES(los_days, 20)[OFFSET(19)] AS p95
  FROM
    filtered_admissions
  GROUP BY
    hospital_expire_flag, discharge_status
),

percentile_rank_7days AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) AS count_less_than_7,
    SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) AS count_less_equal_7
  FROM
    filtered_admissions
  GROUP BY
    hospital_expire_flag
)

SELECT
  ls.discharge_status,
  ls.admission_count,
  ls.p50,
  ls.p75,
  ls.p90,
  ls.p95,
  ROUND((pr.count_less_equal_7 - 1) * 100.0 / pr.count_less_than_7, 2) AS percentile_rank_7days
FROM
  los_stats ls
JOIN
  percentile_rank_7days pr
ON
  ls.hospital_expire_flag = pr.hospital_expire_flag
ORDER BY
  ls.hospital_expire_flag;