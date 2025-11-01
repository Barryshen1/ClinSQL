WITH
-- Define our target population: female inpatients 48-58 with diabetes and heart failure
target_population AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.hadm_id = d1.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag1 ON d1.icd_code = diag1.icd_code AND d1.icd_version = diag1.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.hadm_id = d2.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag2 ON d2.icd_code = diag2.icd_code AND d2.icd_version = diag2.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      -- Diabetes ICD codes (E11-E14)
      (LOWER(diag1.long_title) LIKE '%diabetes%' AND diag1.icd_code LIKE 'E1%')
      -- Heart failure ICD codes (I50)
      OR (LOWER(diag2.long_title) LIKE '%heart failure%' AND diag2.icd_code LIKE 'I50%')
    )
    AND (
      -- Heart failure ICD codes (I50)
      (LOWER(diag1.long_title) LIKE '%heart failure%' AND diag1.icd_code LIKE 'I50%')
      -- Diabetes ICD codes (E11-E14)
      OR (LOWER(diag2.long_title) LIKE '%diabetes%' AND diag2.icd_code LIKE 'E1%')
    )
),

-- Identify GLP-1 prescriptions with subcutaneous route
glp1_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.route,
    p.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE LOWER(p.drug) LIKE '%glp-1%'
     OR LOWER(p.drug) LIKE '%liraglutide%'
     OR LOWER(p.drug) LIKE '%semaglutide%'
     OR LOWER(p.drug) LIKE '%exenatide%'
     OR LOWER(p.drug) LIKE '%dulaglutide%'
     OR LOWER(p.drug) LIKE '%lixisenatide%'
     OR LOWER(p.drug) LIKE '%albiglutide%'
  AND LOWER(p.route) = 'subcutaneous'
),

-- Count patients with GLP-1 in first 24h
first_24h AS (
  SELECT
    COUNT(DISTINCT tp.subject_id) AS total_patients,
    COUNT(DISTINCT CASE WHEN gp.subject_id IS NOT NULL THEN tp.subject_id END) AS glp1_patients
  FROM target_population tp
  LEFT JOIN glp1_prescriptions gp ON
    tp.subject_id = gp.subject_id
    AND tp.hadm_id = gp.hadm_id
    AND gp.starttime BETWEEN tp.admittime AND TIMESTAMP_ADD(tp.admittime, INTERVAL 24 HOUR)
),

-- Count patients with GLP-1 in final 12h
final_12h AS (
  SELECT
    COUNT(DISTINCT tp.subject_id) AS total_patients,
    COUNT(DISTINCT CASE WHEN gp.subject_id IS NOT NULL THEN tp.subject_id END) AS glp1_patients
  FROM target_population tp
  LEFT JOIN glp1_prescriptions gp ON
    tp.subject_id = gp.subject_id
    AND tp.hadm_id = gp.hadm_id
    AND gp.starttime BETWEEN TIMESTAMP_SUB(tp.dischtime, INTERVAL 12 HOUR) AND tp.dischtime
)

-- Final results
SELECT
  'First 24h' AS time_window,
  first_24h.total_patients,
  first_24h.glp1_patients,
  ROUND((first_24h.glp1_patients / first_24h.total_patients) * 100, 2) AS prevalence_percent
FROM first_24h

UNION ALL

SELECT
  'Final 12h' AS time_window,
  final_12h.total_patients,
  final_12h.glp1_patients,
  ROUND((final_12h.glp1_patients / final_12h.total_patients) * 100, 2) AS prevalence_percent
FROM final_12h;