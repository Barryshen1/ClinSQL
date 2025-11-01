SELECT COUNT(DISTINCT admissions.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  ON admissions.subject_id = patients.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON admissions.hadm_id = diag.hadm_id
  AND diag.seq_num = 1
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
  ON diag.icd_code = d_diag.icd_code
  AND diag.icd_version = d_diag.icd_version
WHERE
  patients.gender = 'F'
  AND admissions.insurance = 'Medicare'
  AND admissions.admission_location = 'EMERGENCY ROOM ADMIT'
  AND LOWER(d_diag.long_title) LIKE '%pneumonia%'
  AND (
    patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)
  ) BETWEEN 79 AND 89;