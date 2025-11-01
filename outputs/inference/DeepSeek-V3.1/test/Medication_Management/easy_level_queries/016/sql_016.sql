WITH nitrate_prescriptions AS (
    SELECT
        p.subject_id,
        pr.starttime,
        pr.stoptime,
        DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON pr.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON pr.hadm_id = a.hadm_id
    WHERE
        p.anchor_age BETWEEN 76 AND 86
        AND p.gender = 'M'
        AND LOWER(pr.drug) LIKE '%nitrate%'
        AND pr.route IN ('IV','PO')
        AND pr.stoptime IS NOT NULL
)
SELECT
    APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration_days
FROM nitrate_prescriptions;