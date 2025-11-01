WITH dapt_prescriptions AS (
    SELECT 
        p.subject_id,
        p.hadm_id,
        DATETIME_DIFF(p.stoptime, p.starttime, HOUR) AS duration_hours
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON p.subject_id = pt.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.hadm_id = a.hadm_id
    WHERE 
        pt.gender = 'M'
        AND pt.anchor_age BETWEEN 57 AND 67
        AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
        AND p.stoptime IS NOT NULL
        AND p.starttime IS NOT NULL
        AND (
            LOWER(p.drug) LIKE '%aspirin%'
            OR LOWER(p.drug) LIKE '%clopidogrel%'
            OR LOWER(p.drug) LIKE '%plavix%'
            OR LOWER(p.drug) LIKE '%ticagrelor%'
            OR LOWER(p.drug) LIKE '%brilinta%'
            OR LOWER(p.drug) LIKE '%prasugrel%'
            OR LOWER(p.drug) LIKE '%effient%'
        )
)
SELECT 
    APPROX_QUANTILES(duration_hours, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(duration_hours, 4)[OFFSET(3)] AS q3,
    APPROX_QUANTILES(duration_hours, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_hours, 4)[OFFSET(1)] AS iqr
FROM dapt_prescriptions;