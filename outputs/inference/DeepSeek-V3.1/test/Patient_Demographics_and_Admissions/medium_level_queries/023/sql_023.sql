WITH cohort AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        p.anchor_age,
        a.admission_location,
        a.discharge_location,
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE 
            WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
            WHEN a.discharge_location = 'HOME' THEN 'Home'
            ELSE 'Facility'
        END AS discharge_category
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 41 AND 51
        AND a.admission_location = 'EMERGENCY ROOM'
        AND a.dischtime IS NOT NULL
        AND a.dischtime > a.admittime
)
SELECT 
    discharge_category,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge_7_count,
    ROUND(100 * SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS los_ge_7_percent,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(10)], 2) AS los_10th_percentile
FROM cohort
GROUP BY discharge_category
ORDER BY discharge_category;