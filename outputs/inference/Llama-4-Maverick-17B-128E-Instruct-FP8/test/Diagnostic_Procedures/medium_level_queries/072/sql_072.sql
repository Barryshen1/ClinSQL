WITH 
-- Step 1: Identify Acute Pancreatitis ICD codes
acute_pancreatitis_icd AS (
  SELECT icd_code 
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
  WHERE lower(long_title) LIKE '%acute pancreatitis%' 
  AND icd_version = 9  -- or 10, depending on the codes you find
),
-- Step 2: Patient selection and diagnosis details
patient_diagnosis AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    d.icd_code,
    d.seq_num,
    CASE WHEN d.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_priority
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F' 
  AND p.anchor_age BETWEEN 52 AND 62
  AND d.icd_code IN (SELECT icd_code FROM acute_pancreatitis_icd)
),
-- Step 3: Count diagnostic procedures per admission
procedures_count AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
),
-- Step 4: Calculate LOS and categorize
los_details AS (
  SELECT 
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
    COALESCE(DATETIME_DIFF(i.outtime, i.intime, DAY), 0) AS icu_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
),
-- Step 5: Combine data and analyze
combined_data AS (
  SELECT 
    pd.diagnosis_priority,
    CASE 
      WHEN ld.hospital_los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN ld.hospital_los BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE 'outside range'
    END AS los_category,
    pc.num_procedures
  FROM patient_diagnosis pd
  JOIN procedures_count pc ON pd.hadm_id = pc.hadm_id
  JOIN los_details ld ON pd.hadm_id = ld.hadm_id
  WHERE ld.hospital_los BETWEEN 1 AND 8  -- Filter for LOS range of interest
)
SELECT 
  diagnosis_priority,
  los_category,
  AVG(num_procedures) AS mean_procedures,
  MIN(num_procedures) AS min_procedures,
  MAX(num_procedures) AS max_procedures
FROM combined_data
GROUP BY diagnosis_priority, los_category
ORDER BY diagnosis_priority, los_category;