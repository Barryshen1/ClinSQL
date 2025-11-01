SELECT
    MAX(DATETIME_DIFF(pres.stoptime, pres.starttime, DAY)) AS max_dapt_component_prescription_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
    ON pat.subject_id = pres.subject_id
WHERE
    -- 1. Filter for the specified patient cohort: men aged 84-94
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 84 AND 94

    -- 2. Identify prescriptions for DAPT components (Aspirin or a P2Y12 inhibitor)
    -- Using LOWER and LIKE for robust matching of drug names (generic and brand)
    AND (
        LOWER(pres.drug) LIKE '%aspirin%'
        OR LOWER(pres.drug) LIKE '%clopidogrel%'
        OR LOWER(pres.drug) LIKE '%plavix%'
        OR LOWER(pres.drug) LIKE '%ticagrelor%'
        OR LOWER(pres.drug) LIKE '%brilinta%'
        OR LOWER(pres.drug) LIKE '%prasugrel%'
        OR LOWER(pres.drug) LIKE '%effient%'
    )

    -- 3. Ensure a valid duration can be calculated
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND pres.starttime < pres.stoptime;