SELECT 
  COUNT(DISTINCT adm.hadm_id) AS num_index_admissions
FROM 
  `physionet-data.mimiciv_3_1_hosp.patients` pat
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON pat.subject_id = adm.subject_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.hadm_id = diag.hadm_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
  ON diag.icd_code = icd.icd_code 
  AND diag.icd_version = icd.icd_version
WHERE 
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 70 AND 80
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'EMERGENCY ROOM'
  AND adm.hospital_expire_flag = 0
  AND diag.seq_num = 1
  AND diag.icd_version = 10
  AND diag.icd_code LIKE 'K85%';