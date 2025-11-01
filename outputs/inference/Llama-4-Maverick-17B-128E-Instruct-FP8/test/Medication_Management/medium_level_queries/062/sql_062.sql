WITH 
-- Step 1: Identify patients with diabetes and heart failure
diabetes_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Diabetes%' AND diag.icd_version = 9  
),
heart_failure_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Heart failure%' AND diag.icd_version = 9  
),
cohort AS (
  SELECT pat.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  WHERE pat.gender = 'F' AND pat.anchor_age BETWEEN 50 AND 60
    AND adm.hadm_id IN (SELECT hadm_id FROM diabetes_patients)
    AND adm.hadm_id IN (SELECT hadm_id FROM heart_failure_patients)
),

-- Step 2: Determine medication initiation in the first and last 72 hours
medication_initiation AS (
  SELECT c.hadm_id, 
         CASE 
           WHEN p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 
           ELSE 0 
         END AS glp1_first_72h,
         CASE 
           WHEN p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime THEN 1 
           ELSE 0 
         END AS glp1_last_72h
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) LIKE '%glp-1%'  
),

-- Step 3: Aggregate results
initiation_rates AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN glp1_first_72h = 1 THEN hadm_id END) AS count_glp1_first_72h,
    COUNT(DISTINCT CASE WHEN glp1_last_72h = 1 THEN hadm_id END) AS count_glp1_last_72h,
    COUNT(DISTINCT hadm_id) AS total_patients
  FROM medication_initiation
)

-- Final calculation
SELECT 
  CASE 
    WHEN total_patients = 0 THEN NULL 
    ELSE count_glp1_first_72h / total_patients 
  END AS rate_glp1_first_72h,
  CASE 
    WHEN total_patients = 0 THEN NULL 
    ELSE count_glp1_last_72h / total_patients 
  END AS rate_glp1_last_72h,
  CASE 
    WHEN total_patients = 0 THEN NULL 
    ELSE (count_glp1_last_72h - count_glp1_first_72h) / total_patients 
  END AS absolute_change,
  CASE 
    WHEN count_glp1_first_72h = 0 THEN NULL 
    ELSE SAFE_DIVIDE((count_glp1_last_72h - count_glp1_first_72h), count_glp1_first_72h) 
  END AS relative_change
FROM initiation_rates;