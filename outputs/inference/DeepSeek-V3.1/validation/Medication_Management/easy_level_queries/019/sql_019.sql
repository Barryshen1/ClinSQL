WITH filtered_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
    AND anchor_age BETWEEN 58 AND 68
),
heparin_prescriptions AS (
    SELECT 
        p.subject_id,
        p.hadm_id,
        p.starttime,
        p.stoptime,
        DATETIME_DIFF(
            GREATEST(p.stoptime, p.starttime), 
            LEAST(p.starttime, p.stoptime), 
            DAY
        ) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN filtered_patients fp
        ON p.subject_id = fp.subject_id
    WHERE 
        (LOWER(p.drug) LIKE '%heparin%' OR LOWER(p.drug) LIKE '%enoxaparin%')
        AND p.starttime IS NOT NULL
        AND p.stoptime IS NOT NULL
)
SELECT 
    PERCENTILE_CONT(duration_days, 0.5) OVER() AS median_duration_days
FROM heparin_prescriptions
LIMIT 1;