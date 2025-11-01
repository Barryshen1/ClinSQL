WITH patient_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 73 AND 83
    AND a.dischtime >= a.admittime
),
dka_hhs_admissions AS (
  SELECT 
    pa.hadm_id,
    pa.los_days
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON pa.hadm_id = diag.hadm_id AND diag.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE 
    LOWER(d_diag.long_title) LIKE '%ketoacidosis%'
    OR LOWER(d_diag.long_title) LIKE '%ketoacidotic%'
    OR LOWER(d_diag.long_title) LIKE '%diabetic ketoacidosis%'
    OR LOWER(d_diag.long_title) LIKE '%hyperosmolar%'
    OR LOWER(d_diag.long_title) LIKE '%hyperglycemic state%'
    OR LOWER(d_diag.long_title) LIKE '%hyperosmolar hyperglycemic state%'
    OR LOWER(d_diag.long_title) LIKE '%nonketotic hyperosmolar%'
)
SELECT 
  APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS p25_los
FROM dka_hhs_admissions;