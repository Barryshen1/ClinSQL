WITH filtered_admissions AS (
  SELECT
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_location LIKE '%TRANSFER FROM OTHER HOSP%'
    AND (
      a.discharge_location IN ('HOME', 'FACILITY')
      OR a.hospital_expire_flag = 1
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
los_calc AS (
  SELECT
    CAST(TIMESTAMP_DIFF(dischtime, admittime, SECOND) AS FLOAT64) / 3600 / 24 AS los_days
  FROM
    filtered_admissions
)
SELECT
  AVG(los_days) AS mean_los,
  STDDEV_POP(los_days) AS sd_los,
  (SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percentile_rank_5day_los
FROM
  los_calc;