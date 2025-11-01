WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.hospital_expire_flag,
    a.discharge_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND a.admission_type = 'TRANSFER'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 37 AND 47
),
discharge_groups AS (
  SELECT 
    los_days,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location IN (
        'SKILLED NURSING FACILITY', 
        'REHAB', 
        'CHRONIC/LONG TERM ACUTE CARE'
      ) THEN 'SNF/rehab/LTACH'
    END AS discharge_group
  FROM cohort
  WHERE 
    hospital_expire_flag = 1
    OR discharge_location = 'HOME'
    OR discharge_location IN (
      'SKILLED NURSING FACILITY', 
      'REHAB', 
      'CHRONIC/LONG TERM ACUTE CARE'
    )
),
stats AS (
  SELECT 
    discharge_group,
    COUNT(*) AS n,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100) AS quantiles,
    COUNTIF(los_days <= 5) AS n_5day
  FROM discharge_groups
  GROUP BY discharge_group
)
SELECT 
  discharge_group,
  n,
  mean_los,
  quantiles[OFFSET(25)] AS p25,
  quantiles[OFFSET(50)] AS median,
  quantiles[OFFSET(75)] AS p75,
  quantiles[OFFSET(90)] AS p90,
  quantiles[OFFSET(95)] AS p95,
  (n_5day * 100.0) / n AS percentile_rank_5day
FROM stats
ORDER BY discharge_group;