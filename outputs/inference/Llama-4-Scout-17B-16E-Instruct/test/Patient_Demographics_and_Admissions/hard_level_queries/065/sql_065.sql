SELECT 
    COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 72 AND 82
    AND a.insurance = 'Medicare'
    AND a.admission_location != 'home'
    AND d.icd_code = '411.1'
    AND d.seq_num = 1  -- Principal diagnosis
    AND a.dischtime IS NOT NULL;