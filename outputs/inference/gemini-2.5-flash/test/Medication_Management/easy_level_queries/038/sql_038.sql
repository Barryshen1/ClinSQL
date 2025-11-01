WITH DigoxinPrescriptionDurations AS (
    SELECT
        pr.subject_id,
        DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
    FROM
        `physionet-data.mimiciv_3_1_hosp`.patients AS p
    JOIN
        `physionet-data.mimiciv_3_1_hosp`.prescriptions AS pr
        ON p.subject_id = pr.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 36 AND 46
        AND LOWER(pr.drug) LIKE '%digoxin%'
        AND pr.starttime IS NOT NULL
        AND pr.stoptime IS NOT NULL
        AND pr.stoptime >= pr.starttime -- Ensure a valid, non-negative duration
)
SELECT
    PERCENTILE_CONT(duration_days, 0.75) OVER() - PERCENTILE_CONT(duration_days, 0.25) OVER() AS iqr_digoxin_duration_days
FROM
    DigoxinPrescriptionDurations
LIMIT 1;