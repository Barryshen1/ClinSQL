WITH eligible_admissions AS (
    SELECT 
        a.hadm_id, 
        a.subject_id, 
        a.admittime, 
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 48 AND 58
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
                AND (
                    (d.icd_version = 9 AND d.icd_code LIKE '038%')
                    OR (d.icd_version = 10 AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%'))
                )
        )
        AND NOT EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
                AND (
                    (d.icd_version = 9 AND d.icd_code = '785.52')
                    OR (d.icd_version = 10 AND d.icd_code = 'R65.21')
                )
        )
),
los_and_icu AS (
    SELECT 
        ea.hadm_id,
        ea.subject_id,
        TIMESTAMP_DIFF(ea.dischtime, ea.admittime, DAY) AS los_days,
        CASE 
            WHEN TIMESTAMP_DIFF(ea.dischtime, ea.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN TIMESTAMP_DIFF(ea.dischtime, ea.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
        END AS los_category,
        CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_status
    FROM eligible_admissions ea
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON ea.hadm_id = i.hadm_id
    WHERE TIMESTAMP_DIFF(ea.dischtime, ea.admittime, DAY) BETWEEN 1 AND 8
),
ultrasound_counts AS (
    SELECT 
        p.hadm_id,
        COUNT(*) AS ultrasound_count
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
        ON p.itemid = d.itemid
    WHERE d.label LIKE '%ultrasound%'
    GROUP BY p.hadm_id
)
SELECT 
    l.icu_status,
    l.los_category,
    COUNT(DISTINCT l.subject_id) AS patient_count,
    AVG(COALESCE(u.ultrasound_count, 0)) AS mean_ultrasounds_per_admission
FROM los_and_icu l
LEFT JOIN ultrasound_counts u 
    ON l.hadm_id = u.hadm_id
GROUP BY l.icu_status, l.los_category;