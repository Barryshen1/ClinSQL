WITH 
-- Step 1: Filter patients by age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 53 AND 63
),

-- Step 2: Identify patients with diabetes and heart failure
diabetes_and_hf AS (
  SELECT DISTINCT diag.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd_diag
    ON diag.icd_code = d_icd_diag.icd_code AND diag.icd_version = d_icd_diag.icd_version
  WHERE (LOWER(d_icd_diag.long_title) LIKE '%diabetes%' OR LOWER(d_icd_diag.long_title) LIKE '%diabetic%')
    AND (LOWER(d_icd_diag.long_title) LIKE '%heart failure%' OR LOWER(d_icd_diag.long_title) LIKE '%heart%failure%')
    AND diag.subject_id IN (SELECT subject_id FROM eligible_patients)
),

-- Step 3 & 4: Get admission details and GLP-1 RA prescription details
admissions_details AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pres.starttime,
    pres.drug
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON adm.hadm_id = pres.hadm_id
  WHERE adm.subject_id IN (SELECT subject_id FROM diabetes_and_hf)
    AND LOWER(pres.drug) LIKE '%glp-1%'  -- Simplified filter for GLP-1 RA
),

-- Step 5: Calculate timing of GLP-1 RA initiation
glp1_ra_initiation AS (
  SELECT 
    subject_id,
    hadm_id,
    CASE 
      WHEN starttime <= TIMESTAMP_ADD(admittime, INTERVAL 24 HOUR) THEN 'Within 24 hours of admission'
      WHEN starttime >= TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) THEN 'Within 12 hours before discharge'
      ELSE 'Other'
    END AS initiation_timing
  FROM admissions_details
)

-- Step 6: Calculate percentages
SELECT 
  initiation_timing,
  COUNT(DISTINCT hadm_id) AS count,
  COUNT(DISTINCT hadm_id) * 100.0 / (SELECT COUNT(DISTINCT hadm_id) FROM glp1_ra_initiation) AS percentage
FROM glp1_ra_initiation
WHERE initiation_timing IN ('Within 24 hours of admission', 'Within 12 hours before discharge')
GROUP BY initiation_timing;