SELECT COUNT(*) AS admission_count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  ON admissions.subject_id = patients.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diagnoses
  ON admissions.hadm_id = diagnoses.hadm_id
WHERE
  patients.gender = 'F'
  AND admissions.insurance = 'Medicare'
  AND LOWER(admissions.admission_location) LIKE '%emergency%'
  AND diagnoses.seq_num = 1
  AND (
    (diagnoses.icd_version = 9 AND diagnoses.icd_code = '5770')
    OR
    (diagnoses.icd_version = 10 AND diagnoses.icd_code LIKE 'K85%')
  )
  AND admissions.dischtime IS NOT NULL
  AND (
    patients.anchor_age + EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year
  ) BETWEEN 82 AND 92;