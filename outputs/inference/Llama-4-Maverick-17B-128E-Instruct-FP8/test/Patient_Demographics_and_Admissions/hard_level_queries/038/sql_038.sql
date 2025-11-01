SELECT 
  COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
WHERE 
  p.gender = 'M'
  AND a.insurance = 'Medicare'
  AND a.admission_type = 'TRANSFER FROM HOSP/OTHER FACILITY'
  AND ((d.icd_version = 9 AND d.icd_code = '5856') OR (d.icd_version = 10 AND d.icd_code = 'N18.6'))
  AND d.seq_num = 1  
  AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 90 AND 100;