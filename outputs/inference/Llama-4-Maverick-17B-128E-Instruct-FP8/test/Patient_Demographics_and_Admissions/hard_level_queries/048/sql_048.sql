SELECT 
  COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
WHERE 
  p.gender = 'F'
  AND a.admission_location = 'EMERGENCY ROOM'
  AND a.insurance = 'Medicare'
  AND p.anchor_age BETWEEN 79 AND 89
  AND di.seq_num = 1  
  AND LOWER(dicd.long_title) LIKE '%pneumonia%';