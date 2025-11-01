WITH filtered_stays AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime,
    a.hospital_expire_flag,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.hadm_id = a.hadm_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 81 AND 91
),
temp_events AS (
  SELECT 
    fs.stay_id,
    fs.hospital_expire_flag,
    -- Convert Fahrenheit to Celsius, keep Celsius as-is
    CASE 
        WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5/9 
        ELSE ce.valuenum 
    END AS temp_c
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
    AND ce.charttime >= fs.intime
    AND ce.charttime < DATETIME_ADD(fs.intime, INTERVAL 24 HOUR)
  WHERE 
    ce.itemid IN (223761, 223762)  -- Temperature items (F and C)
    AND ce.valuenum IS NOT NULL    -- Exclude non-numeric values
),
per_stay_temp AS (
  SELECT 
    stay_id,
    hospital_expire_flag,
    AVG(temp_c) AS mean_temp
  FROM temp_events
  GROUP BY stay_id, hospital_expire_flag
),
classified_stays AS (
  SELECT 
    stay_id,
    hospital_expire_flag,
    mean_temp,
    CASE 
        WHEN mean_temp < 36.0 THEN 'Hypothermia (<36.0)'
        WHEN mean_temp < 38.0 THEN 'Normothermia (36.0-37.9)'
        ELSE 'Hyperthermia (>=38.0)'
    END AS temp_category
  FROM per_stay_temp
),
agg_data AS (
  SELECT 
    temp_category,
    COUNT(*) AS N,
    AVG(mean_temp) AS mean_temp,
    APPROX_QUANTILES(mean_temp, 4) AS quantiles,  -- Array: [min, Q1, median, Q3, max]
    AVG(hospital_expire_flag) * 100 AS mi_rate_percent
  FROM classified_stays
  GROUP BY temp_category
)
SELECT 
  temp_category,
  N,
  ROUND(mean_temp, 2) AS mean_temp,
  ROUND(quantiles[SAFE_OFFSET(2)], 2) AS median_temp,  -- Median (Q2)
  ROUND(quantiles[SAFE_OFFSET(3)] - quantiles[SAFE_OFFSET(1)], 2) AS iqr_temp,  -- IQR (Q3-Q1)
  ROUND(mi_rate_percent, 2) AS mi_rate_percent
FROM agg_data
ORDER BY 
  CASE temp_category
    WHEN 'Hypothermia (<36.0)' THEN 1
    WHEN 'Normothermia (36.0-37.9)' THEN 2
    ELSE 3
  END;