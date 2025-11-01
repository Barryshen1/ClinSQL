WITH amiodarone_prescriptions AS (
    SELECT
        p.subject_id,
        p.hadm_id,
        DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON p.subject_id = pt.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.hadm_id = a.hadm_id AND p.subject_id = a.subject_id
    WHERE
        LOWER(p.drug) LIKE '%amiodarone%'
        AND pt.gender = 'M'
        AND pt.anchor_age BETWEEN 62 AND 72
        AND p.stoptime IS NOT NULL
        AND p.starttime IS NOT NULL
)
SELECT
    PERCENTILE_CONT(duration_days, 0.25) OVER() AS q1,
    PERCENTILE_CONT(duration_days, 0.75) OVER() AS q3,
    PERCENTILE_CONT(duration_days, 0.75) OVER() - PERCENTILE_CONT(duration_days, 0.25) OVER() AS iqr
FROM amiodarone_prescriptions
LIMIT 1;