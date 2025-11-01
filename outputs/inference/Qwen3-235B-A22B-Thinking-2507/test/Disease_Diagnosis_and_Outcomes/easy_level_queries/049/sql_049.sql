WITH stroke_admissions AS (
  SELECT 
    admissions.hadm_id,
    patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year) AS age,
    DATETIME_DIFF(admissions.dischtime, admissions.admittime, SECOND) / (60*60*24) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` admissions
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON admissions.subject_id = patients.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON admissions.hadm_id = diag.hadm_id
  WHERE
    patients.gender = 'F'
    AND diag.seq_num = 1
    AND diag.icd_version = 10
    AND diag.icd_code LIKE 'I63%'
    AND admissions.dischtime IS NOT NULL
    AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 50 AND 60
)
SELECT 
  APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS p25_los
FROM stroke_admissions;