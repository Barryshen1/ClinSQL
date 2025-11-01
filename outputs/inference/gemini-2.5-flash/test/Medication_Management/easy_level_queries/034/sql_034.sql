SELECT
    MAX(DATETIME_DIFF(pres.stoptime, pres.starttime, DAY)) AS longest_prescription_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
    ON p.subject_id = pres.subject_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND (
           LOWER(pres.drug) LIKE '%hydralazine%'
        OR LOWER(pres.drug) LIKE '%isosorbide dinitrate%'
    )
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND pres.stoptime >= pres.starttime;