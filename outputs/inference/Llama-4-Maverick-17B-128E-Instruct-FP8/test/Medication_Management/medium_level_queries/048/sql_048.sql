WITH 
-- Step 1: Identify patients with diabetes and heart failure
cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  WHERE p.anchor_age BETWEEN 65 AND 75
  AND diag.icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Diabetes%' OR long_title LIKE '%Heart Failure%')
  AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 96
),
-- Step 2: Extract insulin administration data
insulin_data AS (
  SELECT c.hadm_id, 
         CASE 
           WHEN LOWER(pr.drug) LIKE '%basal%' THEN 'Basal'
           WHEN LOWER(pr.drug) LIKE '%bolus%' THEN 'Bolus'
           WHEN LOWER(pr.drug) LIKE '%sliding%' THEN 'Sliding-Scale'
           ELSE 'Other'
         END AS insulin_type,
         pr.starttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON c.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%insulin%'
),
-- Step 3: Categorize insulin regimens in the first and last 48 hours
insulin_regimens AS (
  SELECT hadm_id, 
         MAX(CASE WHEN starttime <= (SELECT MIN(admittime) FROM `physionet-data.mimiciv_3_1_hosp.admissions` WHERE hadm_id = insulin_data.hadm_id) + INTERVAL 48 HOUR THEN insulin_type END) AS first_48h,
         MAX(CASE WHEN starttime >= (SELECT MAX(dischtime) FROM `physionet-data.mimiciv_3_1_hosp.admissions` WHERE hadm_id = insulin_data.hadm_id) - INTERVAL 48 HOUR THEN insulin_type END) AS last_48h
  FROM insulin_data
  GROUP BY hadm_id
)
-- Step 4: Analyze transitions in insulin regimens
SELECT 
  COUNT(CASE WHEN first_48h = 'Basal' THEN 1 END) AS basal_first_48h,
  COUNT(CASE WHEN last_48h = 'Basal' THEN 1 END) AS basal_last_48h,
  COUNT(CASE WHEN first_48h = 'Bolus' THEN 1 END) AS bolus_first_48h,
  COUNT(CASE WHEN last_48h = 'Bolus' THEN 1 END) AS bolus_last_48h,
  -- Add more counts for other regimens and transitions as needed
  COUNT(*) AS total_patients
FROM insulin_regimens;