SELECT
    APPROX_QUANTILES(
        TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0,
        2
    )[OFFSET(1)] AS median_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pat.subject_id = pr.subject_id
WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 58 AND 68
    AND (
        LOWER(pr.drug) LIKE '%heparin%'
        OR LOWER(pr.drug) LIKE '%enoxaparin%'
    )
    -- Ensure the duration is positive and times are valid
    AND pr.starttime < pr.stoptime;