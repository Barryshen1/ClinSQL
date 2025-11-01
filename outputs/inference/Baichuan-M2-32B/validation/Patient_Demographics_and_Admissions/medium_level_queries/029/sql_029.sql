WITH patient_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
        TIMESTAMP_DIFF(a.admittime, 
            DATE_SUB(DATE(p.anchor_year, 1, 1), INTERVAL p.anchor_age YEAR), 
            YEAR) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND a.dischtime IS NOT NULL
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
            WHERE i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
        )
)
SELECT 
    CASE WHEN hospital_expire_flag = 0 THEN 'Alive' ELSE 'Deceased' END AS survival_status,
    AVG(los) AS mean_los,
    STDDEV(los) AS std_los,
    (COUNT(CASE WHEN los < 7 THEN 1 END) * 100.0) / COUNT(*) AS percent_less_than_7
FROM patient_admissions
WHERE age_at_admission BETWEEN 35 AND 45
GROUP BY survival_status
ORDER BY MIN(hospital_expire_flag);