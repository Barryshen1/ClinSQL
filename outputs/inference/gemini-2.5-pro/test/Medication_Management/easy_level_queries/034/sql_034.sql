SELECT
    MAX(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY)) AS longest_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON p.subject_id = pr.subject_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND (
        LOWER(pr.drug) LIKE '%hydralazine%'
        OR LOWER(pr.drug) LIKE '%isosorbide dinitrate%'
    )
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL;