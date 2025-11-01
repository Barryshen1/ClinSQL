WITH base AS (
    SELECT 
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.discharge_location,
        a.hospital_expire_flag,
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 70 AND 80
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.services` s
            WHERE a.hadm_id = s.hadm_id
                AND s.curr_service IN ('SURG','ORTHO','NEURO','ENT','URO','VSURG','TSURG','CSURG','TRAU','OBGYN','NSURG')
        )
),
categorized AS (
    SELECT 
        hadm_id,
        discharge_location,
        hospital_expire_flag,
        los_days,
        CASE 
            WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
            WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE', 'HOSPICE-HOME') THEN 'home'
            WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB/DISTINCT PART HOSP') THEN 'facility'
            ELSE NULL 
        END AS discharge_category
    FROM base
    WHERE hospital_expire_flag = 1 
        OR discharge_location IN ('HOME', 'HOME HEALTH CARE', 'HOSPICE-HOME', 'SKILLED NURSING FACILITY', 'REHAB/DISTINCT PART HOSP')
)
SELECT
    discharge_category,
    COUNT(*) AS total,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS count_ge7,
    SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS count_ge14,
    SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS prop_ge7,
    SAFE_DIVIDE(SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END), COUNT(*)) AS prop_ge14
FROM categorized
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category
ORDER BY discharge_category;