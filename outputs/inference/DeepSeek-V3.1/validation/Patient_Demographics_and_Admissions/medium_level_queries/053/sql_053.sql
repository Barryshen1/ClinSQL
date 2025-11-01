WITH patient_cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.discharge_location,
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 77 AND 87
        AND adm.admission_type = 'EMERGENCY'
        AND adm.dischtime IS NOT NULL
),
discharge_groups AS (
    SELECT 
        CASE 
            WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
            WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
            WHEN discharge_location = 'HOME' THEN 'Home'
            ELSE 'Other' 
        END AS discharge_group,
        los_days
    FROM patient_cohort
)
SELECT 
    discharge_group,
    APPROX_QUANTILES(los_days, 100)[50] AS median_los,
    APPROX_QUANTILES(los_days, 100)[25] AS q1_los,
    APPROX_QUANTILES(los_days, 100)[75] AS q3_los,
    COUNT(*) AS n
FROM discharge_groups
WHERE discharge_group != 'Other'
GROUP BY discharge_group
ORDER BY discharge_group;