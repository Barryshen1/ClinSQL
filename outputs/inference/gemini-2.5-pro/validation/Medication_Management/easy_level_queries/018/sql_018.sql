SELECT
    MAX(DATETIME_DIFF(presc.stoptime, presc.starttime, DAY)) AS longest_digoxin_prescription_days
FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS presc
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON presc.subject_id = pat.subject_id
WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND presc.drug LIKE 'Digoxin%';