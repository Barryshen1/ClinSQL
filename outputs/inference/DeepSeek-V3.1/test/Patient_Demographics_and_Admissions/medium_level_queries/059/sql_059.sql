WITH cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.discharge_location,
        adm.hospital_expire_flag,
        adm.admission_location,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
        -- Categorize discharge
        CASE
            WHEN adm.discharge_location = 'HOME' THEN 'Home'
            WHEN adm.discharge_location LIKE 'HOSPICE%' THEN 'Hospice'
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital death'
            ELSE 'Other'
        END AS discharge_category
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 75 AND 85
        AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
        AND adm.dischtime IS NOT NULL
),
discharge_groups AS (
    SELECT
        discharge_category,
        COUNT(*) AS total_patients,
        COUNTIF(los >= 7) AS count_los_ge_7,
        COUNTIF(los <= 7) AS count_los_le_7,
        SAFE_DIVIDE(COUNTIF(los >= 7), COUNT(*)) AS proportion,
        SAFE_DIVIDE(COUNTIF(los <= 7), COUNT(*)) AS percentile_rank_7
    FROM cohort
    WHERE discharge_category IN ('Home', 'Hospice', 'In-hospital death')
    GROUP BY discharge_category
)
SELECT
    discharge_category,
    total_patients,
    count_los_ge_7,
    proportion,
    percentile_rank_7 AS seven_day_percentile
FROM discharge_groups
ORDER BY discharge_category;