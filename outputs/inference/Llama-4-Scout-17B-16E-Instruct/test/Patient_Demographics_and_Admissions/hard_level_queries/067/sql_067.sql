SELECT 
  COUNT(DISTINCT a.hadm_id) AS completed_admissions
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 43 AND 53
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'Emergency Department'
  AND d.icd_code IN (
    SELECT icd_code 
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
    WHERE long_title LIKE '%Bowel obstruction%'
  )
  AND a.hospital_expire_flag = 0
  AND a.dischtime IS NOT NULL;