WITH first_admissions AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS admission_rank
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 77 AND 87
        AND a.dischtime IS NOT NULL
)
SELECT 
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] - APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS iqr
FROM first_admissions
WHERE admission_rank = 1;