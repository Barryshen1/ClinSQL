WITH
-- Get female patients aged 57-67
eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
),

-- Get admissions with diabetes and heart failure
diabetes_hf_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients ep ON a.subject_id = ep.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.hadm_id = d1.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag1 ON d1.icd_code = diag1.icd_code
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.hadm_id = d2.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag2 ON d2.icd_code = diag2.icd_code
  WHERE (d1.icd_code LIKE 'E11%' OR d1.icd_code LIKE 'E13%' OR d1.icd_code LIKE 'E14%')
    AND (d2.icd_code LIKE 'I50%')
    AND a.dischtime IS NOT NULL
),

-- Get GLP-1 RA prescriptions in first 48h
early_glp1 AS (
  SELECT DISTINCT p.subject_id, p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN diabetes_hf_admissions dha ON p.hadm_id = dha.hadm_id
  WHERE LOWER(p.drug) LIKE '%exenatide%'
     OR LOWER(p.drug) LIKE '%liraglutide%'
     OR LOWER(p.drug) LIKE '%semaglutide%'
     OR LOWER(p.drug) LIKE '%dulaglutide%'
     OR LOWER(p.drug) LIKE '%lixisenatide%'
     OR LOWER(p.drug) LIKE '%albiglutide%'
  AND p.starttime BETWEEN dha.admittime AND TIMESTAMP_ADD(dha.admittime, INTERVAL 48 HOUR)
),

-- Get GLP-1 RA prescriptions in final 12h
late_glp1 AS (
  SELECT DISTINCT p.subject_id, p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN diabetes_hf_admissions dha ON p.hadm_id = dha.hadm_id
  WHERE LOWER(p.drug) LIKE '%exenatide%'
     OR LOWER(p.drug) LIKE '%liraglutide%'
     OR LOWER(p.drug) LIKE '%semaglutide%'
     OR LOWER(p.drug) LIKE '%dulaglutide%'
     OR LOWER(p.drug) LIKE '%lixisenatide%'
     OR LOWER(p.drug) LIKE '%albiglutide%'
  AND p.starttime BETWEEN TIMESTAMP_SUB(dha.dischtime, INTERVAL 12 HOUR) AND dha.dischtime
),

-- Count patients in each group
counts AS (
  SELECT
    COUNT(DISTINCT dha.subject_id) AS total_patients,
    COUNT(DISTINCT e.subject_id) AS early_glp1_count,
    COUNT(DISTINCT l.subject_id) AS late_glp1_count,
    COUNT(DISTINCT CASE WHEN e.subject_id IS NOT NULL AND l.subject_id IS NOT NULL THEN e.subject_id END) AS both_periods_count
  FROM diabetes_hf_admissions dha
  LEFT JOIN early_glp1 e ON dha.subject_id = e.subject_id AND dha.hadm_id = e.hadm_id
  LEFT JOIN late_glp1 l ON dha.subject_id = l.subject_id AND dha.hadm_id = l.hadm_id
)

-- Calculate prevalence and changes
SELECT
  total_patients,
  early_glp1_count,
  late_glp1_count,
  both_periods_count,
  ROUND(early_glp1_count * 100.0 / total_patients, 2) AS early_prevalence_pct,
  ROUND(late_glp1_count * 100.0 / total_patients, 2) AS late_prevalence_pct,
  ROUND((late_glp1_count - early_glp1_count) * 100.0 / total_patients, 2) AS absolute_change_pct,
  ROUND((late_glp1_count * 1.0 / early_glp1_count - 1) * 100, 2) AS relative_change_pct
FROM counts;