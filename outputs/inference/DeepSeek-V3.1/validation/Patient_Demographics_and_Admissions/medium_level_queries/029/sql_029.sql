WITH icu_admissions AS (
    SELECT 
        i.hadm_id, 
        a.subject_id,
        SUM(i.los) AS total_icu_los,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.hadm_id = a.hadm_id
    GROUP BY i.hadm_id, a.subject_id, a.hospital_expire_flag
)
SELECT 
    CASE 
        WHEN hospital_expire_flag = 1 THEN 'Died in hospital'
        ELSE 'Discharged alive'
    END AS survival_status,
    COUNT(*) AS num_admissions,
    AVG(total_icu_los) AS mean_los,
    STDDEV(total_icu_los) AS sd_los,
    100.0 * SUM(CASE WHEN total_icu_los < 7 THEN 1 ELSE 0 END) / COUNT(*) AS percent_los_less_than_7
FROM icu_admissions ia
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ia.subject_id = p.subject_id
WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
GROUP BY hospital_expire_flag;