SELECT 
    MAX(los) AS max_hospital_los
FROM (
    SELECT 
        p.subject_id,
        p.anchor_age,
        a.hadm_id,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 67 AND 77
        AND d.seq_num = 1  -- primary diagnosis
        AND (
            d.icd_code LIKE 'A41%'   -- sepsis codes
            OR d.icd_code = 'R65.21' -- septic shock
        )
        AND a.dischtime IS NOT NULL  -- ensure LOS is calculable
    GROUP BY p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime
);