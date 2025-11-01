WITH patient_admissions AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.hadm_id,
        a.admission_type,
        a.discharge_location,
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE 
            WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
            WHEN a.discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
            WHEN a.discharge_location = 'HOME' THEN 'Home'
            ELSE 'Other' 
        END AS discharge_category
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 89 AND 99
        AND a.admission_type = 'ELECTIVE'
        AND a.dischtime > a.admittime
)
SELECT 
    discharge_category,
    COUNT(*) AS num_patients,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[50] AS median_los,
    APPROX_QUANTILES(los_days, 100)[75] AS p75_los,
    APPROX_QUANTILES(los_days, 100)[90] AS p90_los,
    ROUND(COUNTIF(los_days < 5) / COUNT(*) * 100, 2) AS percent_los_less_than_5_days
FROM patient_admissions
WHERE discharge_category IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY discharge_category
ORDER BY discharge_category;