WITH 
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 40 AND 50
),
admissions_for_patients AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
),
sepsis_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM admissions_for_patients a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%sepsis%' OR dicd.long_title LIKE '%septic shock%' 
  OR (d.icd_version = 10 AND d.icd_code LIKE 'R65.2%')
),
hospital_los AS (
  SELECT DATETIME_DIFF(dischtime, admittime, HOUR) / 24 AS los_days
  FROM sepsis_admissions
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS Q1,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS Median,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS Q3,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS IQR
FROM hospital_los;