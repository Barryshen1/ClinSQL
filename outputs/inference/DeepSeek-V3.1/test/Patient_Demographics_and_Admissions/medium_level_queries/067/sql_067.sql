WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.discharge_location,
        a.hospital_expire_flag,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
        -- Define discharge groups
        CASE 
            WHEN a.hospital_expire_flag = 1 THEN 'DIED'
            WHEN a.discharge_location LIKE '%HOSPICE%' THEN 'HOSPICE'
            WHEN a.discharge_location LIKE '%HOME%' THEN 'HOME'
            ELSE 'OTHER' 
        END AS discharge_group
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    -- Get the first service for the admission to determine medicine service
    INNER JOIN (
        SELECT 
            subject_id, 
            hadm_id, 
            curr_service,
            ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime ASC) as rn
        FROM `physionet-data.mimiciv_3_1_hosp.services`
    ) s
        ON a.hadm_id = s.hadm_id AND s.rn = 1
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 49 AND 59
        AND s.curr_service = 'MEDICINE'
        AND a.dischtime IS NOT NULL  -- Ensure valid LOS calculation
),

discharge_groups AS (
    SELECT 
        discharge_group,
        COUNT(*) AS total_patients,
        COUNTIF(los >= 7) AS los_ge_7,
        COUNTIF(los >= 14) AS los_ge_14,
        APPROX_QUANTILES(los, 100)[OFFSET(7)] AS los_7th_percentile
    FROM cohort
    WHERE discharge_group IN ('HOME', 'HOSPICE', 'DIED')  -- Filter to relevant groups
    GROUP BY discharge_group
)

SELECT 
    discharge_group,
    total_patients,
    los_ge_7,
    ROUND(los_ge_7 / total_patients * 100, 2) AS proportion_los_ge_7,
    los_ge_14,
    ROUND(los_ge_14 / total_patients * 100, 2) AS proportion_los_ge_14,
    los_7th_percentile
FROM discharge_groups
ORDER BY discharge_group;