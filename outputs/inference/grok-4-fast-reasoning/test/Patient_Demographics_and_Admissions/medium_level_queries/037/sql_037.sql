WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm,
    a.admission_type,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_type != 'EMERGENCY'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 52 AND 62
),
alive_stats AS (
  SELECT
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_alive,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_alive,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_alive,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95_alive
  FROM
    cohort
  WHERE
    hospital_expire_flag = 0
),
dead_stats AS (
  SELECT
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_dead,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_dead,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_dead,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95_dead
  FROM
    cohort
  WHERE
    hospital_expire_flag = 1
),
rank_7 AS (
  SELECT
    (COUNTIF(los_days <= 7) * 100.0 / COUNT(*)) AS pr_7_overall
  FROM
    cohort
)
SELECT
  p50_alive,
  p75_alive,
  p90_alive,
  p95_alive,
  p50_dead,
  p75_dead,
  p90_dead,
  p95_dead,
  pr_7_overall
FROM
  alive_stats,
  dead_stats,
  rank_7;