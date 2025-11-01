SELECT 
  COUNT(DISTINCT a.hadm_id) AS num_index_admissions
FROM 
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 36 AND 46
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'TRANSFER FROM HOSP/OTHER FACILITY'
  AND di.icd_version = 10
  AND di.seq_num = 1
  AND di.icd_code LIKE 'I6%';