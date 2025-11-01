SELECT 
  COUNT(DISTINCT a.hadm_id) AS count_index_admissions
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
LEFT JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id AND diag.seq_num = 1
LEFT JOIN 
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 70 AND 80
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY ROOM ADMIT'
  AND d_diag.long_title LIKE '%Acute pancreatitis%'
  AND diag.icd_version = 10  -- Assuming ICD-10 is used; adjust if necessary;