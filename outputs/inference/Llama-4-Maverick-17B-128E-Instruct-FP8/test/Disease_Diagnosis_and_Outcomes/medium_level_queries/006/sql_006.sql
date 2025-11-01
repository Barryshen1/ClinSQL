WITH 
-- Step 1: Filter patients
patients AS (
  SELECT p.subject_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 64 AND 74
),

-- Step 2: Identify sepsis patients excluding septic shock
sepsis_patients AS (
  SELECT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Sepsis%' AND di.subject_id IN (SELECT subject_id FROM patients)
  EXCEPT DISTINCT
  SELECT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Septic shock%' AND di.subject_id IN (SELECT subject_id FROM patients)
),

-- Step 3: Calculate LOS and in-hospital mortality
admissions_data AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.hadm_id IN (SELECT hadm_id FROM sepsis_patients)
),

-- Step 4: Calculate LOS quartiles
los_quartiles AS (
  SELECT 
    los_hours,
    NTILE(4) OVER (ORDER BY los_hours) AS los_quartile
  FROM admissions_data
),

-- Step 5: Assess CKD and diabetes prevalence
comorbidities AS (
  SELECT di.subject_id, di.hadm_id,
         MAX(CASE WHEN d.long_title LIKE '%Chronic kidney disease%' THEN 1 ELSE 0 END) AS ckd,
         MAX(CASE WHEN d.long_title LIKE '%Diabetes mellitus%' THEN 1 ELSE 0 END) AS diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.hadm_id IN (SELECT hadm_id FROM sepsis_patients)
  GROUP BY di.subject_id, di.hadm_id
)

-- Final query
SELECT 
  lq.los_quartile,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN ad.deathtime IS NOT NULL OR ad.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate,
  SUM(c.ckd) / COUNT(*) AS ckd_prevalence,
  SUM(c.diabetes) / COUNT(*) AS diabetes_prevalence
FROM los_quartiles lq
JOIN admissions_data ad ON lq.los_hours = ad.los_hours
JOIN comorbidities c ON ad.hadm_id = c.hadm_id
GROUP BY lq.los_quartile
ORDER BY lq.los_quartile;