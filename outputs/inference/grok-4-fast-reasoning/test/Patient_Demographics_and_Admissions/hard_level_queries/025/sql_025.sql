SELECT 
  COUNT(DISTINCT a.hadm_id) AS num_index_admissions
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p
ON 
  a.subject_id = p.subject_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
ON 
  a.subject_id = diag.subject_id 
  AND a.hadm_id = diag.hadm_id
WHERE 
  p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'TRANSFER FROM ANOTHER HEALTH CARE FACILITY'
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code LIKE '428%') 
    OR 
    (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
  )
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 65 AND 75;