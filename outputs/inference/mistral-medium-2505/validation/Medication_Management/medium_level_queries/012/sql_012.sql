WITH
-- Define GLP-1 drugs (common examples)
glp1_drugs AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%exenatide%'
     OR LOWER(drug) LIKE '%liraglutide%'
     OR LOWER(drug) LIKE '%dulaglutide%'
     OR LOWER(drug) LIKE '%semaglutide%'
     OR LOWER(drug) LIKE '%lixisenatide%'
     OR LOWER(drug) LIKE '%albiglutide%'
),

-- Get patients with type 2 diabetes and heart failure
target_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag1
    ON p.subject_id = diag1.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d1
    ON diag1.icd_code = d1.icd_code AND diag1.icd_version = d1.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag2
    ON p.subject_id = diag2.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2
    ON diag2.icd_code = d2.icd_code AND diag2.icd_version = d2.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (d1.icd_code LIKE 'E11%' OR d1.long_title LIKE '%type 2 diabetes%')
    AND (d2.icd_code LIKE 'I50%' OR d2.long_title LIKE '%heart failure%')
),

-- Get qualifying admissions (≥72 hours)
qualifying_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN target_patients tp ON a.subject_id = tp.subject_id
  WHERE TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),

-- First 12-hour GLP-1 initiation
first_12h_glp1 AS (
  SELECT DISTINCT qa.subject_id, qa.hadm_id
  FROM qualifying_admissions qa
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON qa.subject_id = p.subject_id AND qa.hadm_id = p.hadm_id
  JOIN glp1_drugs g ON p.drug = g.drug
  WHERE p.starttime BETWEEN qa.admittime
    AND TIMESTAMP_ADD(qa.admittime, INTERVAL 12 HOUR)
),

-- Final 72-hour GLP-1 prevalence
final_72h_glp1 AS (
  SELECT DISTINCT qa.subject_id, qa.hadm_id
  FROM qualifying_admissions qa
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON qa.subject_id = p.subject_id AND qa.hadm_id = p.hadm_id
  JOIN glp1_drugs g ON p.drug = g.drug
  WHERE p.starttime BETWEEN TIMESTAMP_SUB(qa.dischtime, INTERVAL 72 HOUR)
    AND qa.dischtime
),

-- Counts for calculations
counts AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total_patients,
    COUNT(DISTINCT CASE WHEN CONCAT(CAST(subject_id AS STRING), '_', CAST(hadm_id AS STRING)) IN (
      SELECT CONCAT(CAST(subject_id AS STRING), '_', CAST(hadm_id AS STRING)) FROM first_12h_glp1
    ) THEN CONCAT(CAST(subject_id AS STRING), '_', CAST(hadm_id AS STRING)) END) AS first_12h_count,
    COUNT(DISTINCT CASE WHEN CONCAT(CAST(subject_id AS STRING), '_', CAST(hadm_id AS STRING)) IN (
      SELECT CONCAT(CAST(subject_id AS STRING), '_', CAST(hadm_id AS STRING)) FROM final_72h_glp1
    ) THEN CONCAT(CAST(subject_id AS STRING), '_', CAST(hadm_id AS STRING)) END) AS final_72h_count
  FROM qualifying_admissions
)

-- Final results
SELECT
  total_patients,
  first_12h_count,
  final_72h_count,
  ROUND((first_12h_count / total_patients) * 100, 2) AS first_12h_percentage,
  ROUND((final_72h_count / total_patients) * 100, 2) AS final_72h_percentage,
  ROUND(((final_72h_count / total_patients) - (first_12h_count / total_patients)) * 100, 2) AS net_percentage_point_change
FROM counts;