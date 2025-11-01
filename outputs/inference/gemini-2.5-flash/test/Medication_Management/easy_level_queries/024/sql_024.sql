SELECT
    MAX(TIMESTAMP_DIFF(p.stoptime, p.starttime, HOUR)) AS max_dapt_prescription_duration_hours
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON adm.subject_id = p.subject_id AND adm.hadm_id = p.hadm_id
WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 84 AND 94
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime -- Ensures a valid positive duration
    AND (
           LOWER(p.drug) LIKE '%aspirin%'
        OR LOWER(p.drug) LIKE '%clopidogrel%'
        OR LOWER(p.drug) LIKE '%ticagrelor%'
        OR LOWER(p.drug) LIKE '%prasugrel%'
    );