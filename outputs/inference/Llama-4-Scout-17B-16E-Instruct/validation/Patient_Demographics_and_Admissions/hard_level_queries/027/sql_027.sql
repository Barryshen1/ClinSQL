SELECT 
    COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
ON 
    a.subject_id = p.subject_id
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
ON 
    a.hadm_id = d.hadm_id
WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'Emergency Department'
    AND d.seq_num = 1  
    AND d.icd_code IN ('577.0', 'K85.0');