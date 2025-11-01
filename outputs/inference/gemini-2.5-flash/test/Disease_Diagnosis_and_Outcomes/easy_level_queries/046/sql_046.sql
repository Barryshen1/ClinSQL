SELECT
    STDDEV(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS std_dev_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
WHERE
    pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 43 AND 53
    AND diag.seq_num = 1 -- Filter for primary diagnosis
    AND (
        (diag.icd_version = 9 AND (diag.icd_code IN ('430', '431') OR STARTS_WITH(diag.icd_code, '432')))
        OR
        (diag.icd_version = 10 AND (diag.icd_code IN ('I60', 'I61') OR STARTS_WITH(diag.icd_code, 'I62')))
    )
    AND adm.dischtime IS NOT NULL -- Ensure a valid discharge time for LOS calculation;