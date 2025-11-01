SELECT 
    COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.transfers` t 
        ON a.hadm_id = t.hadm_id
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.insurance = 'Medicare'
    AND t.eventtype = 'transfer'
    AND d.seq_num = 1  -- Principal diagnosis
    AND d.icd_code LIKE '428%'  -- Heart failure ICD code;