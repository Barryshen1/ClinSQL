SELECT 
  COUNT(DISTINCT a.hadm_id) AS number_of_admissions
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1  -- Principal diagnosis
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 82 AND 92
  AND a.admission_location = 'Emergency'
  AND a.dischtime IS NOT NULL
  AND (d.icd_code LIKE '577.0' OR d.icd_code LIKE 'K85%');