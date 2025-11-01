SELECT
    AVG(DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0) AS avg_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pa
JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pa.subject_id = pr.subject_id
WHERE
    -- 1. Filter for male patients
    pa.gender = 'M'
    -- 2. Filter for the specified age range (64-74, inclusive)
    AND pa.anchor_age BETWEEN 64 AND 74
    -- 3. Filter for prescriptions containing 'spironolactone' or 'eplerenone'
    AND (
        LOWER(pr.drug) LIKE '%spironolactone%'
        OR LOWER(pr.drug) LIKE '%eplerenone%'
    )
    -- 4. Ensure start and stop times are valid to calculate a positive duration
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.starttime < pr.stoptime;