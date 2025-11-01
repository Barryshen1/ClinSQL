SELECT
    AVG(DATETIME_DIFF(pr.stoptime, pr.starttime, DAY)) AS average_arb_prescription_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON p.subject_id = pr.subject_id
WHERE
    p.gender = 'F' -- Filter for female patients
    AND p.anchor_age BETWEEN 77 AND 87 -- Filter for age between 77 and 87
    AND pr.drug LIKE '%sartan%' -- Identify Angiotensin Receptor Blockers (ARBs)
    AND pr.starttime IS NOT NULL -- Ensure start time is recorded
    AND pr.stoptime IS NOT NULL -- Ensure stop time is recorded
    AND DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) > 0; -- Ensure a positive duration in days;