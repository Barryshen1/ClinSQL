WITH cohort AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
stats AS (
  SELECT
    hospital_expire_flag,
    ROUND(AVG(los_days), 2) AS mean_los,
    APPROX_QUANTILES(los_days, 100) AS los_pctiles,
    COUNT(*) AS total_count,
    COUNTIF(los_days <= 5) AS count_le_5
  FROM
    cohort
  GROUP BY
    hospital_expire_flag
)
SELECT
  CASE
    WHEN hospital_expire_flag = 0 THEN 'Discharged Alive'
    WHEN hospital_expire_flag = 1 THEN 'In-Hospital Death'
  END AS outcome,
  mean_los,
  los_pctiles[OFFSET(50)] AS median_los,
  los_pctiles[OFFSET(75)] AS p75_los,
  los_pctiles[OFFSET(90)] AS p90_los,
  ROUND(100.0 * count_le_5 / total_count, 2) AS pct_rank_5d
FROM
  stats
ORDER BY
  hospital_expire_flag;