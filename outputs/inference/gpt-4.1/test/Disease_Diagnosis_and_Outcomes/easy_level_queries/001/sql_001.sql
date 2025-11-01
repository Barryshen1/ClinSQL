WITH ugib_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    -- UGIB ICD-10 codes
    (icd_version = 10 AND (
      icd_code IN ('K92.0', 'K92.1', 'K92.2')
      OR icd_code BETWEEN 'K25.0' AND 'K25.2'
      OR icd_code BETWEEN 'K26.0' AND 'K26.2'
      OR icd_code BETWEEN 'K27.0' AND 'K27.2'
      OR icd_code BETWEEN 'K28.0' AND 'K28.2'
    ))
    -- UGIB ICD-9 codes (for completeness, add 578.0, 578.1, 578.9)
    OR (icd_version = 9 AND icd_code IN ('5780', '5781', '5789'))
  )
),
copd_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    -- COPD exacerbation ICD-10 codes
    (icd_version = 10 AND icd_code IN ('J44.0', 'J44.1', 'J44.9'))
    -- COPD ICD-9 codes (491.21, 491.22, 496)
    OR (icd_version = 9 AND icd_code IN ('49121', '49122', '496'))
  )
),
target_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN ugib_admissions u ON a.hadm_id = u.hadm_id
  INNER JOIN copd_admissions c ON a.hadm_id = c.hadm_id
  WHERE a.admittime IS NOT NULL AND a.dischtime IS NOT NULL
),
target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 86 AND 96
)
SELECT
  AVG(TIMESTAMP_DIFF(target_admissions.dischtime, target_admissions.admittime, HOUR)/24.0) AS avg_hospital_los_days
FROM target_admissions
INNER JOIN target_patients
  ON target_admissions.subject_id = target_patients.subject_id;