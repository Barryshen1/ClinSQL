SELECT 
    AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_length_of_stay
FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 61 AND 71
    AND d.icd_code IN (
        SELECT 
            icd_code 
        FROM 
            `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
        WHERE 
            long_title LIKE '%Heart failure%'
    )
    AND d.seq_num = 1;  # Primary diagnosis;