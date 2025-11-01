WITH
-- Define heart failure ICD codes (ICD-9 and ICD-10)
heart_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%heart failure%'
    OR icd_code IN (
      '428.0', '428.1', '428.20', '428.21', '428.22', '428.23', '428.30', '428.31', '428.32', '428.33',
      '428.40', '428.41', '428.42', '428.43', '428.9', 'I50.1', 'I50.20', 'I50.21', 'I50.22', 'I50.23',
      'I50.30', 'I50.31', 'I50.32', 'I50.33', 'I50.40', 'I50.41', 'I50.42', 'I50.43', 'I50.9'
    )
),

-- Define CKD and diabetes ICD codes
ckd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%chronic kidney disease%'
    OR LOWER(long_title) LIKE '%ckd%'
    OR icd_code IN ('585.1', '585.2', '585.3', '585.4', '585.5', '585.6', '585.9', 'N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.9')
),

diabetes_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%diabetes%'
    OR icd_code IN (
      '250.00', '250.01', '250.02', '250.03', '250.10', '250.11', '250.12', '250.13',
      '250.20', '250.21', '250.22', '250.23', '250.30', '250.31', '250.32', '250.33',
      '250.40', '250.41', '250.42', '250.43', '250.50', '250.51', '250.52', '250.53',
      '250.60', '250.61', '250.62', '250.63', '250.70', '250.71', '250.72', '250.73',
      '250.80', '250.81', '250.82', '250.83', '250.90', '250.91', '250.92', '250.93',
      'E11.65', 'E11.648', 'E11.649', 'E11.69', 'E11.8', 'E11.9', 'E13.65', 'E13.648',
      'E13.649', 'E13.69', 'E13.8', 'E13.9'
    )
),

-- Get base patient cohort
base_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN TRUE ELSE FALSE END AS in_icu,
    CASE WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) < 8 THEN 'LOS <8' ELSE 'LOS ≥8' END AS los_category
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN heart_failure_codes hf ON d.icd_code = hf.icd_code AND (d.icd_version = '9' OR d.icd_version = '10')
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),

-- Add CKD and diabetes flags
cohort_with_comorbidities AS (
  SELECT
    b.*,
    MAX(CASE WHEN ckd.icd_code IS NOT NULL THEN TRUE ELSE FALSE END) AS has_ckd,
    MAX(CASE WHEN diab.icd_code IS NOT NULL THEN TRUE ELSE FALSE END) AS has_diabetes
  FROM base_cohort b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_ckd
    ON b.subject_id = d_ckd.subject_id AND b.hadm_id = d_ckd.hadm_id
  LEFT JOIN ckd_codes ckd ON d_ckd.icd_code = ckd.icd_code AND (d_ckd.icd_version = '9' OR d_ckd.icd_version = '10')
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_diab
    ON b.subject_id = d_diab.subject_id AND b.hadm_id = d_diab.hadm_id
  LEFT JOIN diabetes_codes diab ON d_diab.icd_code = diab.icd_code AND (d_diab.icd_version = '9' OR d_diab.icd_version = '10')
  GROUP BY
    b.subject_id, b.hadm_id, b.gender, b.anchor_age, b.admittime, b.dischtime,
    b.hospital_expire_flag, b.los_days, b.in_icu, b.los_category
)

-- Final aggregation
SELECT
  CASE WHEN in_icu THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
  los_category,
  COUNT(*) AS patient_count,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag THEN 1 ELSE 0 END) / COUNT(*), 1) AS mortality_percentage,
  ROUND(100 * SUM(CASE WHEN has_ckd THEN 1 ELSE 0 END) / COUNT(*), 1) AS ckd_prevalence_percentage,
  ROUND(100 * SUM(CASE WHEN has_diabetes THEN 1 ELSE 0 END) / COUNT(*), 1) AS diabetes_prevalence_percentage
FROM cohort_with_comorbidities
GROUP BY icu_status, los_category
ORDER BY icu_status, los_category;