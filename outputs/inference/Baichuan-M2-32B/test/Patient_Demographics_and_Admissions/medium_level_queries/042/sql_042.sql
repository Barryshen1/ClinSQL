WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_type NOT IN ('ELECTIVE') -- non-elective
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.hospital_expire_flag IS NOT NULL
),
percentiles AS (
  SELECT
    hospital_expire_flag,
    APPROX_QUANTILES(los_days, 100) AS los_percentiles
  FROM
    cohort
  GROUP BY
    hospital_expire_flag
),
stats AS (
  SELECT
    CASE hospital_expire_flag
      WHEN 0 THEN 'Alive'
      WHEN 1 THEN 'Dead'
    END AS discharge_status,
    AVG(los_days) AS mean_los,
    los_percentiles[OFFSET(50)] AS median_los, -- p50
    los_percentiles[OFFSET(75)] AS p75_los,
    los_percentiles[OFFSET(90)] AS p90_los
  FROM
    percentiles
  GROUP BY
    hospital_expire_flag, discharge_status
),
percentile_rank AS (
  SELECT
    (COUNTIF(los_days <= 5) * 100.0) / COUNT(*) AS pct_rank_5day
  FROM
    cohort
)
SELECT
  discharge_status,
  mean_los,
  median_los,
  p75_los,
  p90_los
FROM
  stats
UNION ALL
SELECT
  'Percentile Rank (5-day stay)' AS discharge_status,
  pct_rank_5day AS mean_los,
  NULL AS median_los,
  NULL AS p75_los,
  NULL AS p90_los
FROM
  percentile_rank
ORDER BY
  CASE discharge_status
    WHEN 'Alive' THEN 1
    WHEN 'Dead' THEN 2
    ELSE 3
  END;