SELECT
    PERCENTILE_CONT(
        TIMESTAMP_DIFF(pres.stoptime, pres.starttime, HOUR) / 24.0,
        0.5
    ) OVER () AS median_heparin_enoxaparin_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON pres.subject_id = p.subject_id
WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (
        LOWER(pres.drug) LIKE '%heparin%'
        OR LOWER(pres.drug) LIKE '%enoxaparin%'
    )
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND TIMESTAMP_DIFF(pres.stoptime, pres.starttime, HOUR) >= 0 -- Ensure stoptime is not prior to starttime;