SELECT
    AVG(DATE_DIFF(p.stoptime, p.starttime, DAY)) AS average_warfarin_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pa
    ON p.subject_id = pa.subject_id
WHERE
    pa.gender = 'M'
    AND pa.anchor_age BETWEEN 43 AND 53
    AND p.drug LIKE '%WARFARIN%'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime;