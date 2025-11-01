WITH qualifying_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 69 AND 79
),
ugib_hadms AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN qualifying_patients qp ON di.subject_id = qp.subject_id
  WHERE di.icd_code IN (
    -- Representative ICD-9 codes for UGIB
    '578.0', '530.7', '530.82',
    -- Representative ICD-10 codes for UGIB
    'K25.0', 'K25.4', 'K26.0', 'K26.4', 'K27.0', 'K27.4', 'I85.01', 'K92.2'
  )
),
copd_hadms AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN qualifying_patients qp ON di.subject_id = qp.subject_id
  WHERE di.icd_code IN (
    -- Representative ICD-9 codes for COPD exacerbation
    '491.21', '491.22', '493.21', '493.22',
    -- Representative ICD-10 codes for COPD exacerbation
    'J44.0', 'J44.1'
  )
),
cohort_hadms AS (
  SELECT hadm_id
  FROM ugib_hadms
  
  INTERSECT DISTINCT
  
  SELECT hadm_id
  FROM copd_hadms
),
los_calc AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort_hadms ch ON a.hadm_id = ch.hadm_id
  WHERE a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) > 0
)
SELECT
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_hospital_los_days
FROM los_calc;