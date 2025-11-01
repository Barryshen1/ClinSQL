WITH amiodarone_prescriptions AS (
    SELECT
        p.subject_id,
        p.hadm_id,
        p.starttime,
        p.stoptime,
        DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON p.subject_id = pt.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.hadm_id = a.hadm_id
    WHERE
        LOWER(p.drug) LIKE '%amiodarone%'
        AND pt.gender = 'F'
        AND pt.anchor_age BETWEEN 59 AND 69
        AND p.starttime IS NOT NULL
        AND p.stoptime IS NOT NULL
        AND p.stoptime > p.starttime
        AND p.starttime >= a.admittime
        AND p.stoptime <= a.dischtime
)
SELECT
    APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS q3,
    APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr
FROM amiodarone_prescriptions;