WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_location,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND (
      LOWER(a.admission_location) LIKE '%transfer%'
      OR LOWER(a.admission_location) LIKE '%transferred%'
      OR LOWER(a.admission_location) LIKE '%other hospital%'
      OR LOWER(a.admission_location) LIKE '%snf%'
      OR LOWER(a.admission_location) LIKE '%rehab%'
      OR LOWER(a.admission_location) LIKE '%ltach%'
    )
)
, discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%skilled nursing%' OR LOWER(discharge_location) LIKE '%snf%' OR LOWER(discharge_location) LIKE '%rehab%' OR LOWER(discharge_location) LIKE '%ltach%' THEN 'SNF/Rehab/LTACH'
      WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
      ELSE 'Other'
    END AS discharge_group
  FROM cohort
)
, stats AS (
  SELECT
    discharge_group,
    COUNT(*) AS n,
    ROUND(AVG(los_days), 2) AS mean_los,
    APPROX_QUANTILES(los_days, 100) AS quantiles,
    -- Percentile rank of 5-day LOS
    ROUND(SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*), 4) AS percentile_rank_5day
  FROM discharge_groups
  WHERE discharge_group IN ('Home', 'SNF/Rehab/LTACH', 'In-hospital mortality')
  GROUP BY discharge_group
)
SELECT
  discharge_group,
  n,
  mean_los,
  ROUND(quantiles[OFFSET(25)], 2) AS p25_los,
  ROUND(quantiles[OFFSET(50)], 2) AS median_los,
  ROUND(quantiles[OFFSET(75)], 2) AS p75_los,
  ROUND(quantiles[OFFSET(90)], 2) AS p90_los,
  ROUND(quantiles[OFFSET(95)], 2) AS p95_los,
  percentile_rank_5day
FROM stats
ORDER BY discharge_group;