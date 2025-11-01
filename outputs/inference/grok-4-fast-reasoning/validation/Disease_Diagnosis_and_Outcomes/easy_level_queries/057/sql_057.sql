SELECT 
  MIN(DATE_DIFF(dischtime, admittime, DAY)) AS min_los_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON a.hadm_id = diag.hadm_id AND diag.seq_num = 1
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
  ON diag.icd_code = icd.icd_code 
  AND diag.icd_version = icd.icd_version
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 88 AND 98
  AND icd.long_title LIKE '%Pneumonia%'
  AND a.admission_location = 'EMERGENCY ROOM';