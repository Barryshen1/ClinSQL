WITH patient_admissions AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.discharge_location,
        adm.hospital_expire_flag,
        adm.admission_location,
        pt.gender,
        pt.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON adm.subject_id = pt.subject_id
    WHERE 
        pt.gender = 'F'
        AND pt.anchor_age BETWEEN 63 AND 73
        AND adm.admission_location LIKE '%Transfer from Hospital%'
),

discharge_categories AS (
    SELECT
        hadm_id,
        admittime,
        dischtime,
        -- Calculate LOS in days
        DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
        -- Define discharge category
        CASE 
            WHEN hospital_expire_flag = 1 THEN 'Death'
            WHEN discharge_location LIKE '%Hospice%' THEN 'Hospice'
            WHEN discharge_location LIKE '%Home%' THEN 'Home'
        END AS discharge_category
    FROM patient_admissions
    WHERE dischtime IS NOT NULL AND admittime IS NOT NULL
        AND dischtime > admittime  -- valid LOS
)

SELECT
    discharge_category,
    COUNT(*) AS num_patients,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(STDDEV(los_days), 2) AS sd_los_days
FROM discharge_categories
WHERE discharge_category IS NOT NULL  -- only include the three categories
GROUP BY discharge_category
ORDER BY discharge_category;