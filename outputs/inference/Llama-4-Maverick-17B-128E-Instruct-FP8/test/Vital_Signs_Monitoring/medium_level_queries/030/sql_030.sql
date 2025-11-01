WITH temp_measurements AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS mean_temp
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ie.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON ie.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' AND p.anchor_age BETWEEN 81 AND 91
    AND ce.itemid = 223762  -- Verify this itemid for temperature
    AND ce.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY 
    ie.stay_id
),
classified_temp AS (
  SELECT 
    stay_id,
    mean_temp,
    CASE 
      WHEN mean_temp < 36.0 THEN '<36.0'
      WHEN mean_temp >= 38.0 THEN '>=38.0'
      ELSE '36.0-37.9'
    END AS temp_category
  FROM 
    temp_measurements
),
mortality AS (
  SELECT 
    ie.stay_id,
    CASE 
      WHEN ad.deathtime IS NOT NULL AND ie.outtime >= ad.deathtime THEN 1 
      WHEN ad.hospital_expire_flag = 1 THEN 1 
      ELSE 0 
    END AS died
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` ad ON ie.hadm_id = ad.hadm_id
),
stats AS (
  SELECT 
    ct.temp_category,
    COUNT(*) AS N,
    AVG(ct.mean_temp) AS mean,
    APPROX_QUANTILES(ct.mean_temp, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(ct.mean_temp, 100)[OFFSET(75)] - APPROX_QUANTILES(ct.mean_temp, 100)[OFFSET(25)] AS IQR,
    AVG(m.died) * 100 AS MI_rate
  FROM 
    classified_temp ct
  INNER JOIN 
    mortality m ON ct.stay_id = m.stay_id
  GROUP BY 
    ct.temp_category
)
SELECT 
  temp_category,
  N,
  mean,
  median,
  IQR,
  MI_rate
FROM 
  stats;