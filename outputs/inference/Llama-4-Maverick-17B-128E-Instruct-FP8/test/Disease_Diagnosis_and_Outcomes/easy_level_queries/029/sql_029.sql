WITH patient_cohort AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 69 AND 79
),
ugib_copd_patients AS (
  SELECT DISTINCT a.hadm_id
  FROM patient_cohort a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE (LOWER(d_diag.long_title) LIKE '%upper gastrointestinal bleeding%' OR diag.icd_code LIKE '578.0%')  -- UGIB codes
  AND (LOWER(d_diag.long_title) LIKE '%chronic obstructive pulmonary disease%' OR diag.icd_code LIKE '491.21%' OR diag.icd_code LIKE 'J44.1%')  -- COPD exacerbation codes
),
hospital_los AS (
  SELECT a.hadm_id, DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN ugib_copd_patients u ON a.hadm_id = u.hadm_id
)
SELECT APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los
FROM hospital_los;