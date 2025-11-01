SELECT
    AVG(TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY)) AS avg_warfarin_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pres.subject_id = pat.subject_id
WHERE
    -- Define the patient cohort: men aged 43-53
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
    -- Identify warfarin prescriptions
    AND LOWER(pres.drug) LIKE 'warfarin%'
    -- Ensure the duration is calculable and positive
    AND pres.stoptime > pres.starttime;