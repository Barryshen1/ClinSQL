SELECT
    MAX(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS max_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND diag.seq_num = 1 -- Primary diagnosis
    AND diag.icd_version = 10
    AND (
        diag.icd_code LIKE 'A40.%' -- Streptococcal sepsis
        OR diag.icd_code LIKE 'A41.%' -- Other sepsis
        OR diag.icd_code LIKE 'R65.2%' -- Severe sepsis / Septic shock
    );