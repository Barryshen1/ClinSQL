SELECT
    MAX(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS max_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 58 AND 68;