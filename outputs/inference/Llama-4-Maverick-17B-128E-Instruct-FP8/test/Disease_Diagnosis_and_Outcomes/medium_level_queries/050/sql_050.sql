WITH patient_info AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admit
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 75 AND 85
),
sepsis_patients AS (
  SELECT DISTINCT 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE 
    dicd.long_title LIKE '%Sepsis%' 
    AND dicd.long_title NOT LIKE '%septic shock%'
),
comorbidities AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN dicd.long_title LIKE '%Chronic kidney disease%' THEN 1 ELSE 0 END) AS CKD,
    MAX(CASE WHEN dicd.long_title LIKE '%Diabetes%' THEN 1 ELSE 0 END) AS diabetes,
    MAX(CASE WHEN dicd.long_title LIKE '%Atrial fibrillation%' THEN 1 ELSE 0 END) AS AFib,
    MAX(CASE WHEN dicd.long_title LIKE '%Hypertension%' THEN 1 ELSE 0 END) AS hypertension
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  GROUP BY 
    hadm_id
),
los_info AS (
  SELECT 
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM 
    patient_info
),
mortality_stratified AS (
  SELECT 
    pi.hospital_expire_flag,
    li.los <= 5 AS los_leq_5,
    c.CKD,
    c.diabetes,
    c.AFib,
    c.hypertension
  FROM 
    patient_info pi
  INNER JOIN 
    sepsis_patients sp ON pi.hadm_id = sp.hadm_id
  INNER JOIN 
    comorbidities c ON pi.hadm_id = c.hadm_id
  INNER JOIN 
    los_info li ON pi.hadm_id = li.hadm_id
)
SELECT 
  los_leq_5,
  CKD,
  diabetes,
  AFib,
  hypertension,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS total_deaths,
  SUM(hospital_expire_flag) / COUNT(*) * 100 AS mortality_percentage
FROM 
  mortality_stratified
GROUP BY 
  los_leq_5, CKD, diabetes, AFib, hypertension
ORDER BY 
  los_leq_5, CKD, diabetes, AFib, hypertension;