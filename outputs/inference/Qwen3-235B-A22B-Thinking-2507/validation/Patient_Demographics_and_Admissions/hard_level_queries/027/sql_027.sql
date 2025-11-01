SELECT COUNT(DISTINCT admissions.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  ON admissions.subject_id = patients.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON admissions.hadm_id = diag.hadm_id
WHERE
  patients.gender = 'F'
  AND admissions.insurance = 'Medicare'
  AND admissions.admission_location = 'EMERGENCY ROOM ADMIT'
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code = '5770')
    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
  )
  AND (
    patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)
  ) BETWEEN 70 AND 80;