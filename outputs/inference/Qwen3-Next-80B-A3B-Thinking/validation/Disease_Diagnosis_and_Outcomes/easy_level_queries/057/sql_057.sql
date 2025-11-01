SELECT MIN(DATE_DIFF(admissions.dischtime, admissions.admittime, DAY)) AS min_los
FROM `physionet-data.mimiciv_3_1_hosp.patients` AS patients
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
  ON patients.subject_id = admissions.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diagnoses_icd
  ON admissions.hadm_id = diagnoses_icd.hadm_id
  AND diagnoses_icd.seq_num = 1
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_icd
  ON diagnoses_icd.icd_code = d_icd.icd_code
  AND diagnoses_icd.icd_version = d_icd.icd_version
WHERE patients.gender = 'F'
  AND patients.anchor_age BETWEEN 88 AND 98
  AND d_icd.long_title LIKE '%community-acquired pneumonia%';