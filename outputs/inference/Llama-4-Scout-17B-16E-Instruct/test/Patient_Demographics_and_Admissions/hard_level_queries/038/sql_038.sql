SELECT 
    COUNT(DISTINCT a.hadm_id) AS number_of_admissions
FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'Transfer from another hospital'
    AND (d.icd_code = '585.6' OR (d.icd_code = 'N18.6' AND d.icd_version = 10))
    AND d.seq_num = 1  -- Principal diagnosis;