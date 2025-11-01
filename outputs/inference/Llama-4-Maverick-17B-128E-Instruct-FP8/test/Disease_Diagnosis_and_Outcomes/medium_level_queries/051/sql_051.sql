WITH 
-- Step 1: Filter patients by age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 51 AND 61
),

-- Step 2: Identify admissions for these patients
admissions_data AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS care_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE a.subject_id IN (SELECT subject_id FROM eligible_patients)
),

-- Step 3: Calculate LOS and stratify
los_data AS (
  SELECT hadm_id, care_type, 
         DATE_DIFF(dischtime, admittime, DAY) AS los,
         CASE
           WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 2 THEN '1-2'
           WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 3 AND 5 THEN '3-5'
           WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 6 AND 9 THEN '6-9'
           ELSE '>=10'
         END AS los_stratified
  FROM admissions_data
),

-- Step 4: Approximate Charlson Comorbidity Index (simplified)
charlson_comorbidity AS (
  SELECT d.hadm_id,
         SUM(CASE
           WHEN d.icd_code IN ('585.1', '585.2', '585.3', '585.4', '585.5', '585.6', '585.9') AND d.icd_version = 9 THEN 2  -- CKD
           WHEN d.icd_code LIKE '250%' AND d.icd_version = 9 THEN 1  -- Diabetes
           -- Add more conditions as needed for icd_version = 9 and 10
           ELSE 0
         END) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 9  -- Filter by icd_version
  GROUP BY d.hadm_id
),

-- Step 5: Combine data and calculate outcomes
combined_data AS (
  SELECT l.hadm_id, l.care_type, l.los, l.los_stratified,
         CASE WHEN c.charlson_score BETWEEN 0 AND 1 THEN '0-1'
              WHEN c.charlson_score = 2 THEN '2'
              ELSE '>=3'
         END AS charlson_stratified,
         a.hospital_expire_flag,
         CASE WHEN d.icd_code LIKE '585%' AND d.icd_version = 9 THEN 1 ELSE 0 END AS ckd,
         CASE WHEN d.icd_code LIKE '250%' AND d.icd_version = 9 THEN 1 ELSE 0 END AS diabetes
  FROM los_data l
  JOIN admissions_data a ON l.hadm_id = a.hadm_id
  LEFT JOIN charlson_comorbidity c ON l.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON l.hadm_id = d.hadm_id AND d.icd_version = 9
)

-- Final aggregation
SELECT care_type, los_stratified, charlson_stratified,
       COUNT(*) AS total_patients,
       AVG(hospital_expire_flag) * 100 AS mortality_percent,
       APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
       AVG(ckd) * 100 AS ckd_prevalence,
       AVG(diabetes) * 100 AS diabetes_prevalence
FROM combined_data
GROUP BY care_type, los_stratified, charlson_stratified
ORDER BY care_type, los_stratified, charlson_stratified;