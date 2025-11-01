WITH
-- Define diabetes and acute HF ICD codes
diabetes_codes AS (
  SELECT icd_code, icd_version FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '250%')
     OR (icd_version = 10 AND icd_code LIKE 'E1%')
),
acute_hf_codes AS (
  SELECT icd_code, icd_version FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),

-- Get patients with diabetes and acute HF
target_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.hadm_id = d1.hadm_id
  JOIN diabetes_codes dc ON d1.icd_code = dc.icd_code AND d1.icd_version = dc.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.hadm_id = d2.hadm_id
  JOIN acute_hf_codes ahf ON d2.icd_code = ahf.icd_code AND d2.icd_version = ahf.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
),

-- Define medication classes
medication_classes AS (
  SELECT
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) LIKE '%sulfonylurea%' OR
           LOWER(drug) LIKE '%glimepiride%' OR
           LOWER(drug) LIKE '%glyburide%' OR
           LOWER(drug) LIKE '%glipizide%' THEN 'Sulfonylurea'
      WHEN LOWER(drug) LIKE '%dpp-4%' OR
           LOWER(drug) LIKE '%sitagliptin%' OR
           LOWER(drug) LIKE '%saxagliptin%' OR
           LOWER(drug) LIKE '%linagliptin%' THEN 'DPP-4'
      WHEN LOWER(drug) LIKE '%sglt2%' OR
           LOWER(drug) LIKE '%empagliflozin%' OR
           LOWER(drug) LIKE '%canagliflozin%' OR
           LOWER(drug) LIKE '%dapagliflozin%' THEN 'SGLT2'
      WHEN LOWER(drug) LIKE '%glp-1%' OR
           LOWER(drug) LIKE '%exenatide%' OR
           LOWER(drug) LIKE '%liraglutide%' OR
           LOWER(drug) LIKE '%dulaglutide%' THEN 'GLP-1'
      WHEN LOWER(drug) LIKE '%thiazolidinedione%' OR
           LOWER(drug) LIKE '%pioglitazone%' OR
           LOWER(drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE 'Other'
    END AS medication_class,
    drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY drug
),

-- Get medications for target patients
patient_medications AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.admittime,
    p.dischtime,
    m.medication_class,
    pr.starttime AS medication_starttime
  FROM target_patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.hadm_id = pr.hadm_id
  JOIN medication_classes m ON LOWER(pr.drug) = LOWER(m.drug)
  WHERE m.medication_class != 'Other'
),

-- Calculate first 24h prevalence
first_24h_prevalence AS (
  SELECT
    medication_class,
    COUNT(DISTINCT subject_id) AS patients_with_medication,
    COUNT(DISTINCT CASE WHEN medication_starttime <= TIMESTAMP_ADD(admittime, INTERVAL 24 HOUR) THEN subject_id END) AS patients_in_window
  FROM patient_medications
  GROUP BY medication_class
),

-- Calculate final 12h prevalence
final_12h_prevalence AS (
  SELECT
    medication_class,
    COUNT(DISTINCT subject_id) AS patients_with_medication,
    COUNT(DISTINCT CASE WHEN medication_starttime >= TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) THEN subject_id END) AS patients_in_window
  FROM patient_medications
  GROUP BY medication_class
),

-- Combine results
combined_results AS (
  SELECT
    f.medication_class,
    f.patients_with_medication AS total_patients,
    f.patients_in_window AS first_24h_patients,
    l.patients_in_window AS final_12h_patients,
    p.subject_count
  FROM first_24h_prevalence f
  JOIN final_12h_prevalence l ON f.medication_class = l.medication_class
  CROSS JOIN (SELECT COUNT(DISTINCT subject_id) AS subject_count FROM target_patients) p
)

-- Final calculation with percentages
SELECT
  medication_class,
  ROUND((first_24h_patients / subject_count) * 100, 2) AS first_24h_prevalence_percent,
  ROUND((final_12h_patients / subject_count) * 100, 2) AS final_12h_prevalence_percent,
  ROUND(((final_12h_patients / subject_count) * 100) - ((first_24h_patients / subject_count) * 100), 2) AS net_change_pp
FROM combined_results
ORDER BY medication_class;