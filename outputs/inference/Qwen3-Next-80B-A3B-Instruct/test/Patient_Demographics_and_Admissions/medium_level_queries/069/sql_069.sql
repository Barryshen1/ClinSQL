WITH cohort AS (
  SELECT
    a.hospital_expire_flag,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type = 'EMERGENCY'
    AND a.dischtime IS NOT NULL
),
proportions AS (
  SELECT
    hospital_expire_flag,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS proportion_los_ge_7
  FROM
    cohort
  GROUP BY
    hospital_expire_flag
),
percentile_7 AS (
  SELECT
    SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile_rank_7day_los
  FROM
    cohort
)
SELECT
  p.hospital_expire_flag,
  p.proportion_los_ge_7,
  pr.percentile_rank_7day_los
FROM
  proportions p
CROSS JOIN
  percentile_7 pr;