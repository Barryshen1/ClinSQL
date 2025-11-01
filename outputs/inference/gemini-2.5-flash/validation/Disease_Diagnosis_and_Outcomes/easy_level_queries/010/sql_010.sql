SELECT
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25_hospital_los_days
FROM
    (
        SELECT
            DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON adm.subject_id = pat.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
            ON adm.hadm_id = diag.hadm_id
        WHERE
            pat.gender = 'F'
            AND pat.anchor_age BETWEEN 49 AND 59
            AND adm.dischtime IS NOT NULL
            AND adm.admittime IS NOT NULL
            AND adm.dischtime > adm.admittime
            AND diag.seq_num = 1 -- Primary diagnosis
            AND (
                (diag.icd_version = 10 AND diag.icd_code IN ('J440', 'J441')) -- ICD-10 COPD exacerbation codes
                OR
                (diag.icd_version = 9 AND diag.icd_code IN ('49121', '4928')) -- ICD-9 COPD exacerbation codes
            )
    ) AS cohort_admissions_los;