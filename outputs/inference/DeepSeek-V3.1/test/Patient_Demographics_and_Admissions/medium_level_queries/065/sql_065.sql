WITH eligible_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.discharge_location,
        a.hospital_expire_flag,
        p.anchor_age,
        p.gender,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 75 AND 85
        AND NOT EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
            WHERE a.hadm_id = i.hadm_id
        )
),
categorized AS (
    SELECT 
        *,
        CASE
            WHEN hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
            WHEN discharge_location = 'HOME' THEN 'Discharged Home'
            WHEN discharge_location = 'HOSPICE' THEN 'Discharged to Hospice'
            ELSE 'Other'
        END AS outcome_group
    FROM eligible_admissions
)
SELECT 
    outcome_group,
    COUNT(*) AS n_admissions,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(STDDEV(los_days), 2) AS sd_los_days
FROM categorized
WHERE outcome_group != 'Other'
GROUP BY outcome_group
ORDER BY outcome_group;