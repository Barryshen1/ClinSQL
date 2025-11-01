WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),
aggregated AS (
  SELECT DISTINCT
    hospital_expire_flag,
    COUNT(*) OVER (PARTITION BY hospital_expire_flag) AS num_admissions,
    PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY hospital_expire_flag) AS p50_los,
    PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY hospital_expire_flag) AS p75_los,
    PERCENTILE_CONT(los_days, 0.9) OVER (PARTITION BY hospital_expire_flag) AS p90_los,
    PERCENTILE_CONT(los_days, 0.95) OVER (PARTITION BY hospital_expire_flag) AS p95_los,
    SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) OVER (PARTITION BY hospital_expire_flag) * 1.0 / COUNT(*) OVER (PARTITION BY hospital_expire_flag) AS percentile_rank_10day_los
  FROM
    filtered_admissions
)
SELECT
  hospital_expire_flag,
  num_admissions,
  p50_los,
  p75_los,
  p90_los,
  p95_los,
  percentile_rank_10day_los
FROM
  aggregated
ORDER BY
  hospital_expire_flag;