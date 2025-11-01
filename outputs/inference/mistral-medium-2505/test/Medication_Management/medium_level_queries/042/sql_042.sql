WITH
-- Define diabetes and acute HF ICD codes
diabetes_codes AS (
  SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'
),
acute_hf_codes AS (
  SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('I50.1', 'I50.2', 'I50.9')
),

-- Get eligible patients (female, age 51-61, with diabetes and acute HF)
eligible_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.hadm_id = d1.hadm_id
  JOIN diabetes_codes dc ON d1.icd_code = dc.icd_code
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.hadm_id = d2.hadm_id
  JOIN acute_hf_codes ahf ON d2.icd_code = ahf.icd_code
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND d1.seq_num = 1  -- Primary diagnosis for diabetes
    AND d2.seq_num = 1  -- Primary diagnosis for acute HF
),

-- Get insulin prescriptions
insulin_prescriptions AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    drug,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'insulin'
      ELSE NULL
    END AS medication_type
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%insulin%'
),

-- Get oral agent prescriptions
oral_agents_prescriptions AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    drug,
    CASE
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'oral_agent'
      WHEN LOWER(drug) LIKE '%glipizide%' THEN 'oral_agent'
      WHEN LOWER(drug) LIKE '%glyburide%' THEN 'oral_agent'
      WHEN LOWER(drug) LIKE '%glimepiride%' THEN 'oral_agent'
      WHEN LOWER(drug) LIKE '%pioglitazone%' THEN 'oral_agent'
      WHEN LOWER(drug) LIKE '%rosiglitazone%' THEN 'oral_agent'
      ELSE NULL
    END AS medication_type
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%metformin%'
    OR LOWER(drug) LIKE '%glipizide%'
    OR LOWER(drug) LIKE '%glyburide%'
    OR LOWER(drug) LIKE '%glimepiride%'
    OR LOWER(drug) LIKE '%pioglitazone%'
    OR LOWER(drug) LIKE '%rosiglitazone%'
),

-- Combine all diabetes medications
diabetes_medications AS (
  SELECT subject_id, hadm_id, starttime, stoptime, drug, medication_type
  FROM insulin_prescriptions
  UNION ALL
  SELECT subject_id, hadm_id, starttime, stoptime, drug, medication_type
  FROM oral_agents_prescriptions
  WHERE medication_type IS NOT NULL
),

-- First 48 hours medication usage
first_48h_meds AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    dm.medication_type,
    COUNT(DISTINCT dm.drug) AS drug_count
  FROM eligible_patients e
  JOIN diabetes_medications dm ON e.subject_id = dm.subject_id AND e.hadm_id = dm.hadm_id
  WHERE dm.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 48 HOUR)
  GROUP BY e.subject_id, e.hadm_id, dm.medication_type
),

-- Final 24 hours medication usage
final_24h_meds AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    dm.medication_type,
    COUNT(DISTINCT dm.drug) AS drug_count
  FROM eligible_patients e
  JOIN diabetes_medications dm ON e.subject_id = dm.subject_id AND e.hadm_id = dm.hadm_id
  WHERE dm.starttime BETWEEN TIMESTAMP_SUB(e.dischtime, INTERVAL 24 HOUR) AND e.dischtime
  GROUP BY e.subject_id, e.hadm_id, dm.medication_type
),

-- Medication changes analysis
medication_changes AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    -- First 48h medications
    MAX(CASE WHEN f.medication_type = 'insulin' THEN 1 ELSE 0 END) AS first_48h_insulin,
    MAX(CASE WHEN f.medication_type = 'oral_agent' THEN 1 ELSE 0 END) AS first_48h_oral,
    -- Final 24h medications
    MAX(CASE WHEN l.medication_type = 'insulin' THEN 1 ELSE 0 END) AS final_24h_insulin,
    MAX(CASE WHEN l.medication_type = 'oral_agent' THEN 1 ELSE 0 END) AS final_24h_oral
  FROM eligible_patients e
  LEFT JOIN first_48h_meds f ON e.subject_id = f.subject_id AND e.hadm_id = f.hadm_id
  LEFT JOIN final_24h_meds l ON e.subject_id = l.subject_id AND e.hadm_id = l.hadm_id
  GROUP BY e.subject_id, e.hadm_id
),

-- Calculate medication change categories
change_categories AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN first_48h_insulin = 1 AND final_24h_insulin = 1 THEN 'continued_insulin'
      WHEN first_48h_insulin = 0 AND final_24h_insulin = 1 THEN 'initiated_insulin'
      WHEN first_48h_insulin = 1 AND final_24h_insulin = 0 THEN 'discontinued_insulin'
      ELSE NULL
    END AS insulin_change,
    CASE
      WHEN first_48h_oral = 1 AND final_24h_oral = 1 THEN 'continued_oral'
      WHEN first_48h_oral = 0 AND final_24h_oral = 1 THEN 'initiated_oral'
      WHEN first_48h_oral = 1 AND final_24h_oral = 0 THEN 'discontinued_oral'
      ELSE NULL
    END AS oral_change
  FROM medication_changes
),

-- Count of eligible patients
eligible_count AS (
  SELECT COUNT(DISTINCT subject_id) AS count FROM eligible_patients
)

-- Final results
SELECT
  -- Percentages in first 48 hours
  (SELECT COUNT(DISTINCT subject_id) FROM first_48h_meds WHERE medication_type = 'insulin') /
    NULLIF((SELECT count FROM eligible_count), 0) * 100 AS percent_insulin_first_48h,
  (SELECT COUNT(DISTINCT subject_id) FROM first_48h_meds WHERE medication_type = 'oral_agent') /
    NULLIF((SELECT count FROM eligible_count), 0) * 100 AS percent_oral_first_48h,

  -- Percentages in final 24 hours
  (SELECT COUNT(DISTINCT subject_id) FROM final_24h_meds WHERE medication_type = 'insulin') /
    NULLIF((SELECT count FROM eligible_count), 0) * 100 AS percent_insulin_final_24h,
  (SELECT COUNT(DISTINCT subject_id) FROM final_24h_meds WHERE medication_type = 'oral_agent') /
    NULLIF((SELECT count FROM eligible_count), 0) * 100 AS percent_oral_final_24h,

  -- Medication change counts
  COUNT(DISTINCT CASE WHEN insulin_change = 'continued_insulin' THEN subject_id END) AS continued_insulin,
  COUNT(DISTINCT CASE WHEN insulin_change = 'initiated_insulin' THEN subject_id END) AS initiated_insulin,
  COUNT(DISTINCT CASE WHEN insulin_change = 'discontinued_insulin' THEN subject_id END) AS discontinued_insulin,
  COUNT(DISTINCT CASE WHEN oral_change = 'continued_oral' THEN subject_id END) AS continued_oral,
  COUNT(DISTINCT CASE WHEN oral_change = 'initiated_oral' THEN subject_id END) AS initiated_oral,
  COUNT(DISTINCT CASE WHEN oral_change = 'discontinued_oral' THEN subject_id END) AS discontinued_oral
FROM change_categories;