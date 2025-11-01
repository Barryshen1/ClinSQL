SELECT COUNT(DISTINCT admissions.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  ON admissions.subject_id = patients.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diagnoses_icd
  ON admissions.hadm_id = diagnoses_icd.hadm_id
  AND diagnoses_icd.seq_num = 1
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_icd_diagnoses
  ON diagnoses_icd.icd_code = d_icd_diagnoses.icd_code
  AND diagnoses_icd.icd_version = d_icd_diagnoses.icd_version
WHERE patients.gender = 'M'
  AND patients.anchor_age BETWEEN 72 AND 82
  AND admissions.insurance = 'Medicare'
  AND admissions.admission_location = 'TRANSFER FROM HOSP/OTHER FACILITY'
  AND d_icd_diagnoses.long_title LIKE '%Unstable Angina%'
  AND admissions.dischtime IS NOT NULL;