SELECT
    MAX(DATE_DIFF(pr.stoptime, pr.starttime, DAY)) AS longest_digoxin_prescription_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON adm.subject_id = pr.subject_id AND adm.hadm_id = pr.hadm_id
WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 82 AND 92
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime;