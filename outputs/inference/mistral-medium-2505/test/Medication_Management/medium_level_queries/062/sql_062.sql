WITH
-- Define diabetes and heart failure ICD codes
diabetes_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%'
),
heart_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I50%'
),

-- Get female patients 50-60 with diabetes and heart failure
eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.subject_id = d1.subject_id AND a.hadm_id = d1.hadm_id
  JOIN diabetes_codes dc ON d1.icd_code = dc.icd_code
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.subject_id = d2.subject_id AND a.hadm_id = d2.hadm_id
  JOIN heart_failure_codes hfc ON d2.icd_code = hfc.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
),

-- Get admissions for eligible patients with sufficient length of stay
eligible_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients ep ON a.subject_id = ep.subject_id
  WHERE TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),

-- GLP-1 medications (injectable)
glp1_meds AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%liraglutide%'
     OR LOWER(drug) LIKE '%semaglutide%'
     OR LOWER(drug) LIKE '%dulaglutide%'
     OR LOWER(drug) LIKE '%exenatide%'
),

-- GLP-1 prescriptions in first 72 hours
first_72h_glp1 AS (
  SELECT DISTINCT ea.hadm_id
  FROM eligible_admissions ea
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON ea.hadm_id = p.hadm_id
  JOIN glp1_meds gm ON p.drug = gm.drug
  WHERE p.starttime BETWEEN ea.admittime AND TIMESTAMP_ADD(ea.admittime, INTERVAL 72 HOUR)
),

-- GLP-1 prescriptions in final 72 hours
final_72h_glp1 AS (
  SELECT DISTINCT ea.hadm_id
  FROM eligible_admissions ea
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON ea.hadm_id = p.hadm_id
  JOIN glp1_meds gm ON p.drug = gm.drug
  WHERE p.starttime BETWEEN TIMESTAMP_SUB(ea.dischtime, INTERVAL 72 HOUR) AND ea.dischtime
),

-- Counts for each period
counts AS (
  SELECT
    COUNT(DISTINCT ea.hadm_id) AS total_admissions,
    COUNT(DISTINCT f72.hadm_id) AS first_72h_count,
    COUNT(DISTINCT fin72.hadm_id) AS final_72h_count
  FROM eligible_admissions ea
  LEFT JOIN first_72h_glp1 f72 ON ea.hadm_id = f72.hadm_id
  LEFT JOIN final_72h_glp1 fin72 ON ea.hadm_id = fin72.hadm_id
)

-- Final results
SELECT
  total_admissions,
  first_72h_count,
  final_72h_count,
  (first_72h_count / total_admissions) * 100 AS first_72h_rate,
  (final_72h_count / total_admissions) * 100 AS final_72h_rate,
  (final_72h_count - first_72h_count) AS absolute_change,
  CASE
    WHEN first_72h_count = 0 THEN NULL
    ELSE ((final_72h_count - first_72h_count) / first_72h_count) * 100
  END AS relative_change_percentage
FROM counts;