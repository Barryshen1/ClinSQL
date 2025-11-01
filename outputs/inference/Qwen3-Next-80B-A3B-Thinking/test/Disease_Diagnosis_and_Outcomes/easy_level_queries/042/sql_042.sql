SELECT AVG(TIMESTAMP_DIFF(admissions.dischtime, admissions.admittime, DAY)) AS avg_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` admissions
JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
  ON admissions.subject_id = patients.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON admissions.hadm_id = diag.hadm_id
WHERE diag.seq_num = 1
  AND patients.gender = 'F'
  AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 78 AND 88
  AND (diag.icd_code LIKE 'I20%' 
       OR diag.icd_code LIKE 'I21%' 
       OR diag.icd_code LIKE 'I22%' 
       OR diag.icd_code LIKE 'I23%' 
       OR diag.icd_code LIKE 'I24%');