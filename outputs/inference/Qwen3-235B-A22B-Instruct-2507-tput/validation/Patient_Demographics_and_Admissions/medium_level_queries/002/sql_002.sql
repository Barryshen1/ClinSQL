WITH first_service AS (
  SELECT 
    hadm_id,
    curr_service,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.services`
),
admissions_with_service AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN first_service s ON a.hadm_id = s.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE s.rn = 1
    AND s.curr_service LIKE '%MED%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
categorized_los AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) = 'home' THEN 'Discharged home'
      ELSE 'Discharged to facility'
    END AS discharge_category
  FROM admissions_with_service
),
los_stats AS (
  SELECT
    discharge_category,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 1000) AS quantiles,
    AVG(CASE WHEN los_days <= 10 THEN 1.0 ELSE 0.0 END) AS pct_los_le_10_days
  FROM categorized_los
  GROUP BY discharge_category
)
SELECT
  discharge_category,
  mean_los,
  quantiles[OFFSET(250)] AS p25_los,   -- 25th percentile
  quantiles[OFFSET(500)] AS p50_los,   -- 50th percentile
  quantiles[OFFSET(750)] AS p75_los,   -- 75th percentile
  quantiles[OFFSET(900)] AS p90_los,   -- 90th percentile
  pct_los_le_10_days
FROM los_stats
ORDER BY discharge_category;