SELECT
    AVG(DATETIME_DIFF(pr.stoptime, pr.starttime, DAY)) AS average_digoxin_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
ON
    p.subject_id = pr.subject_id
WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND pr.drug = 'DIGOXIN'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime;