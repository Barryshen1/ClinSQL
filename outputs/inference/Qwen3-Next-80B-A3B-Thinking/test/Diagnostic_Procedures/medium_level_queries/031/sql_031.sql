WITH admissions_with_aki AS (
    SELECT 
        a.hadm_id,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 38 AND 48
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE 
                d.hadm_id = a.hadm_id
                AND (
                    (d.icd_version = 9 AND d.icd_code LIKE '584%')
                    OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
                )
        )
        AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
icu_status AS (
    SELECT 
        hadm_id,
        CASE WHEN COUNT(stay_id) > 0 THEN 'Yes' ELSE 'No' END AS icu_used
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY hadm_id
),
lab_counts AS (
    SELECT 
        hadm_id,
        COUNT(*) AS lab_count
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    GROUP BY hadm_id
)
SELECT
    CASE 
        WHEN a.los_days BETWEEN 1 AND 4 THEN '1-4 days'
        ELSE '5-7 days'
    END AS stay_duration,
    i.icu_used,
    AVG(COALESCE(l.lab_count, 0)) AS mean_lab_count,
    MIN(COALESCE(l.lab_count, 0)) AS min_lab_count,
    MAX(COALESCE(l.lab_count, 0)) AS max_lab_count
FROM admissions_with_aki a
LEFT JOIN icu_status i ON a.hadm_id = i.hadm_id
LEFT JOIN lab_counts l ON a.hadm_id = l.hadm_id
GROUP BY stay_duration, i.icu_used;