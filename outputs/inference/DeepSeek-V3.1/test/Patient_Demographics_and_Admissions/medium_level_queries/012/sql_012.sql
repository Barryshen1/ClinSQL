WITH patient_admissions AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.discharge_location,
        adm.hospital_expire_flag,
        pt.gender,
        pt.anchor_age,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON adm.subject_id = pt.subject_id
    WHERE pt.gender = 'M'
        AND pt.anchor_age BETWEEN 75 AND 85
),
categorized_admissions AS (
    SELECT 
        *,
        CASE 
            WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
            WHEN discharge_location LIKE '%HOME%' THEN 'Discharged home'
            WHEN discharge_location LIKE '%SNF%' 
                OR discharge_location LIKE '%REHAB%'
                OR discharge_location LIKE '%FACILITY%' 
                THEN 'Discharged to facility'
            ELSE 'Other'
        END AS discharge_category
    FROM patient_admissions
),
filtered_admissions AS (
    SELECT 
        * 
    FROM categorized_admissions 
    WHERE discharge_category IN ('Discharged home', 'Discharged to facility', 'In-hospital death')
        AND los_days >= 7
),
category_stats AS (
    SELECT 
        discharge_category,
        COUNT(*) OVER (PARTITION BY discharge_category) AS category_total,
        COUNT(*) AS count_los_ge_7,
        COUNT(*) / COUNT(*) OVER (PARTITION BY discharge_category) AS proportion,
        PERCENT_RANK() OVER (PARTITION BY discharge_category ORDER BY los_days) AS percentile_rank
    FROM filtered_admissions
    GROUP BY discharge_category, los_days
)
SELECT 
    discharge_category,
    MAX(category_total) AS total_admissions_in_category,
    MAX(count_los_ge_7) AS count_los_ge_7,
    MAX(proportion) AS proportion,
    percentile_rank
FROM category_stats
GROUP BY discharge_category, percentile_rank
ORDER BY discharge_category, percentile_rank;