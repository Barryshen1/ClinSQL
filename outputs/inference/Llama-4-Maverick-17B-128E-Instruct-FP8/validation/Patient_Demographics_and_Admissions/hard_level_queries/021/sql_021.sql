SELECT COUNT(DISTINCT a.hadm_id)
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
WHERE p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'EMERGENCY ROOM ADMIT'
  AND a.dischtime IS NOT NULL
  AND p.anchor_age BETWEEN 82 AND 92
  AND ((d.icd_version = 9 AND d.icd_code = '5770' AND d.seq_num = 1)
       OR (d.icd_version = 10 AND d.icd_code LIKE 'K85%' AND d.seq_num = 1));