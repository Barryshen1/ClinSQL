WITH target_population AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_location = 'TRANSFER FROM ANOTHER HOSPITAL'
    AND a.dischtime IS NOT NULL
    AND (
      a.discharge_location LIKE '%HOME%'
      OR a.discharge_location LIKE '%FACILITY%'
      OR a.hospital_expire_flag = 1
    )
),

percentile_ranks AS (
  SELECT
    los_days,
    PERCENT_RANK() OVER (ORDER BY los_days) AS percentile_rank
  FROM
    target_population
)

SELECT
  -- Basic statistics for the entire population
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los,

  -- Percentile rank for 5-day LOS
  ROUND(MAX(CASE WHEN los_days = 5 THEN percentile_rank ELSE NULL END), 4) AS percentile_rank_5day_los
FROM
  percentile_ranks;