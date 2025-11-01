WITH digoxin_prescriptions AS (
    SELECT
        p.subject_id,
        pr.starttime,
        pr.stoptime,
        DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0 AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON pr.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 86 AND 96
        AND LOWER(pr.drug) LIKE '%digoxin%'
        AND pr.starttime IS NOT NULL
        AND pr.stoptime IS NOT NULL
)
SELECT
    APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS q3,
    APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr
FROM digoxin_prescriptions;