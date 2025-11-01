WITH temp_first_24h AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    AVG(ch.valuenum) AS mean_temp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ch 
    ON ie.stay_id = ch.stay_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND ch.itemid = 223762  -- Temperature Celsius
    AND ch.valuenum IS NOT NULL
    AND ch.charttime >= ie.intime
    AND ch.charttime < DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY ie.stay_id, ie.subject_id, ie.hadm_id
),
temp_categories AS (
  SELECT 
    stay_id,
    subject_id,
    hadm_id,
    mean_temp,
    CASE 
      WHEN mean_temp < 36.0 THEN '<36.0'
      WHEN mean_temp BETWEEN 36.0 AND 37.9 THEN '36.0-37.9'
      WHEN mean_temp >= 38.0 THEN '>=38.0'
    END AS temp_category
  FROM temp_first_24h
)
SELECT 
  temp_category,
  COUNT(*) AS N,
  AVG(mean_temp) AS mean_mean_temp,
  APPROX_QUANTILES(mean_temp, 100)[50] AS median_mean_temp,
  APPROX_QUANTILES(mean_temp, 100)[75] - APPROX_QUANTILES(mean_temp, 100)[25] AS iqr_mean_temp,
  100.0 * SUM(adm.hospital_expire_flag) / COUNT(*) AS mortality_rate_percent
FROM temp_categories tc
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
  ON tc.hadm_id = adm.hadm_id
GROUP BY temp_category
ORDER BY temp_category;