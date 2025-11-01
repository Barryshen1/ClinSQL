WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CAST(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24 AS FLOAT64) AS los_days,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_type != 'ELECTIVE'
    AND a.admission_location LIKE '%MEDICINE%'
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24 > 0
),

stats AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) AS n,
    AVG(los_days) AS mean_los,
    PERCENTILE_DISC(los_days, 0.5) OVER() AS median_los,
    PERCENTILE_DISC(los_days, 0.75) OVER() AS p75_los,
    PERCENTILE_DISC(los_days, 0.9) OVER() AS p90_los
  FROM
    cohort
  GROUP BY
    hospital_expire_flag
),

percentile_rank AS (
  SELECT
    PERCENT_RANK() OVER(ORDER BY los_days) AS rank_5day
  FROM
    cohort
  WHERE
    los_days = 5
  LIMIT 1
)

SELECT
  CASE WHEN s.hospital_expire_flag = 0 THEN 'Discharged Alive' ELSE 'In-Hospital Death' END AS status,
  s.n AS count,
  ROUND(s.mean_los, 2) AS mean_los,
  ROUND(s.median_los, 2) AS median_los,
  ROUND(s.p75_los, 2) AS p75_los,
  ROUND(s.p90_los, 2) AS p90_los,
  (SELECT rank_5day FROM percentile_rank) AS percentile_rank_5day
FROM
  stats s
ORDER BY
  s.hospital_expire_flag;