WITH 
-- Step 1: Identify relevant ICD codes for heart failure and COPD
heart_failure_icd_codes AS (
  SELECT icd_code 
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
  WHERE icd_version = 10 AND lower(long_title) LIKE '%heart failure%'
),
copd_icd_codes AS (
  SELECT icd_code 
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
  WHERE icd_version = 10 AND lower(long_title) LIKE '%chronic obstructive pulmonary disease%'
),

-- Step 2: Identify admissions with heart failure and COPD
admissions_with_conditions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE d.icd_code IN (SELECT icd_code FROM heart_failure_icd_codes) 
     OR d.icd_code IN (SELECT icd_code FROM copd_icd_codes)
),

-- Step 3: Filter patients based on age, gender, and conditions
filtered_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, 
         p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM admissions_with_conditions)
    AND p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 77 AND 87
),

-- Step 4: Calculate hospital LOS
hospital_los AS (
  SELECT hadm_id, DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM filtered_admissions
)

-- Step 5: Calculate SD of hospital LOS
SELECT STDDEV(los_days) AS sd_los_days
FROM hospital_los;