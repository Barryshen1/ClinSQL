SELECT
    AVG(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0) AS average_digoxin_prescription_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON p.subject_id = pr.subject_id
WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND LOWER(pr.drug) LIKE '%digoxin%'
    -- Ensure start and stop times are available to calculate a valid duration
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    -- Ensure the duration is positive
    AND pr.stoptime > pr.starttime;