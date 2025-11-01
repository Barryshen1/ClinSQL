SELECT COUNT(DISTINCT a.hadm_id)
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
WHERE p.gender = 'M'
AND p.anchor_age BETWEEN 43 AND 53
AND a.insurance = 'Medicare'
AND a.admission_location = 'EMERGENCY ROOM'
AND (
  (d.icd_version = 9 AND d.icd_code LIKE '250.1%')  
  OR (d.icd_version = 10 AND d.icd_code IN ('E10.1', 'E11.1'))  
)
AND d.seq_num = 1;