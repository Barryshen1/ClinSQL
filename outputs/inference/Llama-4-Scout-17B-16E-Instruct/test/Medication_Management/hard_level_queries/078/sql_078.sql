WITH 
-- Patient demographics and admission details
patient_data AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    a.hadm_id, 
    a.admittime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' AND 
    p.anchor_age BETWEEN 74 AND 84
),

-- Medication data within the first 24 hours
medication_data AS (
  SELECT 
    p.subject_id, 
    p.hadm_id, 
    COUNT(DISTINCT p.drug) AS medication_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.pharmacy` p
  JOIN 
    patient_data pd 
  ON p.subject_id = pd.subject_id AND p.hadm_id = pd.hadm_id
  WHERE 
    p.starttime < TIMESTAMP_ADD(pd.admittime, INTERVAL 1 DAY)
  GROUP BY 
    p.subject_id, 
    p.hadm_id
),

-- ICU stay details
icu_stays AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Combine patient and medication data
patient_medication AS (
  SELECT 
    pd.subject_id, 
    pd.hadm_id, 
    pd.admittime, 
    pd.hospital_expire_flag,
    COALESCE(md.medication_count, 0) AS medication_count
  FROM 
    patient_data pd
  LEFT JOIN 
    medication_data md 
  ON pd.subject_id = md.subject_id AND pd.hadm_id = md.hadm_id
),

-- Calculate medication complexity distribution
medication_complexity AS (
  SELECT 
    APPROX_QUANTILES(medication_count, 1000) AS quantiles
  FROM 
    patient_medication
)

SELECT 
  AVG(medication_count) AS mean_complexity,
  MIN(medication_count) AS min_complexity,
  MAX(medication_count) AS max_complexity,
  STDDEV(medication_count) AS sd_complexity,
  COUNT(CASE WHEN im.hadm_id IS NOT NULL THEN 1 END) AS icu_patients_count,
  COUNT(CASE WHEN pm.medication_count > (SELECT ARRAY_LENGTH(APPROX_QUANTILES(medication_count, 1000)) - 250 FROM medication_complexity) THEN 1 END) AS top_quartile_count,
  COUNT(CASE WHEN pm.hospital_expire_flag = 1 THEN 1 END) AS mortality_count
FROM 
  patient_medication pm
LEFT JOIN 
  icu_stays im ON pm.hadm_id = im.hadm_id;