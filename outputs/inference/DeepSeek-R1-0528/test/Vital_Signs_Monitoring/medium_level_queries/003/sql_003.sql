WITH patient_stays AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id, 
    ie.intime, 
    ie.outtime,
    -- Calculate age at hospital admission
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON ie.subject_id = pt.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE 
    pt.gender = 'M'
    -- Age filter: 71-81 years
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 71 AND 81
),

temperature_data AS (
  SELECT 
    p.stay_id,
    AVG(ch.valuenum) AS avg_temp
  FROM patient_stays p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ch
    ON p.stay_id = ch.stay_id
  WHERE 
    ch.itemid = 223762  -- Temperature Celsius
    AND ch.valuenum IS NOT NULL
    AND ch.charttime >= p.intime
    AND ch.charttime < DATETIME_ADD(p.intime, INTERVAL 48 HOUR)
  GROUP BY p.stay_id
),

mi_diagnoses AS (
  SELECT 
    hadm_id,
    1 AS mi_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    -- ICD-9 codes for MI
    (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code = '412')) OR 
    -- ICD-10 codes for MI
    (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
  GROUP BY hadm_id  -- Unique admissions with MI
),

categorized_data AS (
  SELECT 
    t.stay_id,
    t.avg_temp,
    CASE 
      WHEN t.avg_temp < 36.0 THEN '<36.0 (Hypothermic)'
      WHEN t.avg_temp >= 36.0 AND t.avg_temp < 38.0 THEN '36.0–37.9 (Normothermic)'
      WHEN t.avg_temp >= 38.0 THEN '≥38.0 (Hyperthermic)'
    END AS temp_category,
    COALESCE(m.mi_flag, 0) AS mi_flag
  FROM temperature_data t
  LEFT JOIN patient_stays p ON t.stay_id = p.stay_id
  LEFT JOIN mi_diagnoses m ON p.hadm_id = m.hadm_id
)

SELECT 
  temp_category,
  COUNT(*) AS num_stays,
  AVG(avg_temp) AS mean_temp,
  APPROX_QUANTILES(avg_temp, 100)[OFFSET(50)] AS median_temp,
  APPROX_QUANTILES(avg_temp, 100)[OFFSET(25)] AS q1_temp,
  APPROX_QUANTILES(avg_temp, 100)[OFFSET(75)] AS q3_temp,
  APPROX_QUANTILES(avg_temp, 100)[OFFSET(75)] - APPROX_QUANTILES(avg_temp, 100)[OFFSET(25)] AS iqr_temp,
  AVG(mi_flag) AS mi_rate
FROM categorized_data
GROUP BY temp_category
ORDER BY 
  -- Order categories logically
  CASE temp_category
    WHEN '<36.0 (Hypothermic)' THEN 1
    WHEN '36.0–37.9 (Normothermic)' THEN 2
    WHEN '≥38.0 (Hyperthermic)' THEN 3
  END;