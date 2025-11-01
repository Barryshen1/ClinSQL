SELECT COUNT(*) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  ON admissions.subject_id = patients.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diagnoses_icd
  ON admissions.hadm_id = diagnoses_icd.hadm_id 
  AND diagnoses_icd.seq_num = 1
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_icd_diagnoses
  ON diagnoses_icd.icd_code = d_icd_diagnoses.icd_code 
  AND diagnoses_icd.icd_version = d_icd_diagnoses.icd_version
WHERE 
  patients.gender = 'F'
  AND admissions.insurance = 'Medicare'
  AND admissions.admission_location IN ('EMERGENCY ROOM ADMIT', 'TRANSFER FROM HOSPITAL EMERGENCY ROOM')
  AND LOWER(d_icd_diagnoses.long_title) LIKE '%acute cholecystitis%'
  AND LOWER(d_icd_diagnoses.long_title) NOT LIKE '%chronic%'
  AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 38 AND 48;