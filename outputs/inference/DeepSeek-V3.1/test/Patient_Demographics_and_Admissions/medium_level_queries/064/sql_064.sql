WITH patient_icu AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        i.hadm_id,
        i.stay_id,
        i.los,
        a.discharge_location,
        a.hospital_expire_flag,
        CASE 
            WHEN a.discharge_location = 'HOME' THEN 'Home'
            WHEN a.discharge_location LIKE 'HOSPICE%' THEN 'Hospice'
            WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
            ELSE 'Other' 
        END AS outcome
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON p.subject_id = i.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON i.hadm_id = a.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 63 AND 73
        AND i.los IS NOT NULL
)

SELECT 
    outcome,
    COUNT(stay_id) AS n,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
    ROUND(100 * SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) / COUNT(stay_id), 2) AS pct_lte_10_days
FROM patient_icu
WHERE outcome IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY outcome
ORDER BY outcome;