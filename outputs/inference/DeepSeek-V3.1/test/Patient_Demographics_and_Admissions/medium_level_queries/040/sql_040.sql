WITH cohort AS (
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
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 70 AND 80
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.services` s
            WHERE adm.hadm_id = s.hadm_id
                AND UPPER(s.curr_service) LIKE '%SURG%'
        )
),

discharge_groups AS (
    SELECT 
        hadm_id,
        los_days,
        CASE 
            WHEN hospital_expire_flag = 1 THEN 'death'
            WHEN discharge_location = 'HOME' THEN 'home'
            WHEN discharge_location IN ('SNF', 'REHAB', 'LTAC') THEN 'facility'
            ELSE 'other'
        END AS discharge_category
    FROM cohort
)

SELECT 
    discharge_category,
    COUNT(*) AS total_admissions,
    COUNTIF(los_days >= 7) AS los_ge_7,
    ROUND(COUNTIF(los_days >= 7) / COUNT(*) * 100, 2) AS pct_los_ge_7,
    COUNTIF(los_days >= 14) AS los_ge_14,
    ROUND(COUNTIF(los_days >= 14) / COUNT(*) * 100, 2) AS pct_los_ge_14
FROM discharge_groups
WHERE discharge_category IN ('home', 'facility', 'death')
GROUP BY discharge_category
ORDER BY discharge_category;