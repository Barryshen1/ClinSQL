SELECT
    MAX(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY)) AS max_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 58 AND 68
    AND adm.admittime IS NOT NULL -- Ensure admission time is recorded
    AND adm.dischtime IS NOT NULL -- Ensure discharge time is recorded for completed stays
;