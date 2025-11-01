SELECT COUNT(DISTINCT admissions.hadm_id) AS count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  ON admissions.subject_id = patients.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diagnoses_icd
  ON admissions.hadm_id = diagnoses_icd.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_icd
  ON diagnoses_icd.icd_code = d_icd.icd_code
  AND diagnoses_icd.icd_version = d_icd.icd_version
WHERE
  patients.gender = 'M'
  AND admissions.insurance = 'Medicare'
  AND admissions.admission_location = 'Transfer from SNF'
  AND diagnoses_icd.seq_num = 1
  AND d_icd.long_title = 'Dehydration'
  AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 43 AND 53;