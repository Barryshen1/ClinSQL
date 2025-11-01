SELECT 
    discharge_group,
    COUNT(*) AS total_patients,
    AVG(los_days) AS mean_los,
    STDDEV(los_days) AS std_los,
    SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_los_le_7
FROM (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.discharge_location,
        a.hospital_expire_flag,
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE 
            WHEN a.hospital_expire_flag = 1 THEN 'in-hospital mortality'
            WHEN a.discharge_location = 'Home' THEN 'discharged home'
            ELSE 'discharged to facility'
        END AS discharge_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 67 AND 77
        AND a.admittime IS NOT NULL
        AND a.dischtime IS NOT NULL
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
            WHERE proc.subject_id = a.subject_id 
                AND proc.hadm_id = a.hadm_id
        )
) 
GROUP BY discharge_group
ORDER BY discharge_group;