SELECT 
  COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 62 AND 72
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'Emergency'
  AND (d.icd_code = '780.2' OR d.icd_code = 'R55');