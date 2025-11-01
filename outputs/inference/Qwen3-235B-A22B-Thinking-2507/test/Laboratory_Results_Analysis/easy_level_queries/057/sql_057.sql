WITH pneumonia_admissions AS (
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code 
    AND diag.icd_version = d_diag.icd_version
  WHERE pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) = 61
    AND LOWER(d_diag.long_title) LIKE '%pneumonia%'
),
creatinine_values AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS creatinine_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.label = 'Creatinine'
    AND dli.fluid = 'Blood'
    AND le.valuenum IS NOT NULL
),
nadir_per_admission AS (
  SELECT 
    pa.hadm_id,
    MIN(cv.creatinine_value) AS nadir_creat
  FROM pneumonia_admissions pa
  INNER JOIN creatinine_values cv
    ON pa.hadm_id = cv.hadm_id
  GROUP BY pa.hadm_id
)
SELECT 
  APPROX_QUANTILES(nadir_creat, 1000)[OFFSET(750)] 
  - APPROX_QUANTILES(nadir_creat, 1000)[OFFSET(250)] AS iqr
FROM nadir_per_admission;