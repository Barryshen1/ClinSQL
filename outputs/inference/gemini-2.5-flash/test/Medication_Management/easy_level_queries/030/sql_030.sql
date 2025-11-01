SELECT
    PERCENTILE_CONT(DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR), 0.25) OVER () AS q1_amiodarone_duration_hours
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON a.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
WHERE
    p.gender = 'F'
    AND LOWER(pr.drug) LIKE '%amiodarone%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 42 AND 52;