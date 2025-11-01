WITH cohort AS (
    SELECT 
        adm.hadm_id,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE 
            WHEN adm.hospital_expire_flag = 1 THEN 'Death'
            WHEN adm.discharge_location = 'HOME' THEN 'Home'
            WHEN adm.discharge_location LIKE 'HOSPICE%' THEN 'Hospice'
        END AS discharge_category
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 74 AND 84
        AND adm.admission_type = 'MEDICAL'  -- Changed from 'MEDICINE' to 'MEDICAL'
        AND adm.discharge_location IS NOT NULL
),
stats AS (
    SELECT 
        discharge_category,
        COUNT(*) AS n_admissions,
        AVG(los_days) AS mean_los,
        PERCENTILE_CONT(los_days, 0.5) AS median_los,  -- Changed to aggregate function
        SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) AS n_short_stay
    FROM cohort
    WHERE discharge_category IS NOT NULL
    GROUP BY discharge_category
)
SELECT 
    discharge_category,
    n_admissions,
    mean_los,
    median_los,
    n_short_stay / n_admissions AS proportion_short_stay
FROM stats
ORDER BY discharge_category;