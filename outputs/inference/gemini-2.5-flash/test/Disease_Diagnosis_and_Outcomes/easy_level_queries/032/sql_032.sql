SELECT
    PERCENTILE_CONT(hospital_los_days, 0.75) OVER () - PERCENTILE_CONT(hospital_los_days, 0.25) OVER () AS iqr_hospital_los_days
FROM
    (
        SELECT
            DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS hospital_los_days
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON adm.subject_id = pat.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
            ON adm.hadm_id = diag.hadm_id
        WHERE
            pat.gender = 'M'
            AND pat.anchor_age BETWEEN 81 AND 91
            AND diag.seq_num = 1 -- Primary diagnosis
            AND (
                (diag.icd_version = 10 AND LEFT(diag.icd_code, 3) = 'N17') -- ICD-10 for Acute Kidney Failure
                OR
                (diag.icd_version = 9 AND LEFT(diag.icd_code, 3) = '584')   -- ICD-9 for Acute Kidney Failure
            )
            AND adm.dischtime IS NOT NULL -- Ensure discharge time exists for LOS calculation
    ) AS sub
LIMIT 1;