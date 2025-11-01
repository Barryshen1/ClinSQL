SELECT
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS percentile_25th_los_days
FROM (
    SELECT
        DATETIME_DIFF(admit.dischtime, admit.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS admit
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON admit.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON admit.hadm_id = diag.hadm_id
    WHERE
        pat.gender = 'F'
        AND (pat.anchor_age + (EXTRACT(YEAR FROM admit.admittime) - pat.anchor_year)) BETWEEN 40 AND 50
        AND diag.seq_num = 1 -- Only consider primary diagnosis
        AND (
            -- ICD-9 codes for Ischemic Heart Disease/ACS
            (diag.icd_version = 9 AND (
                diag.icd_code LIKE '410%' OR
                diag.icd_code LIKE '411%' OR
                diag.icd_code LIKE '412%' OR
                diag.icd_code LIKE '413%' OR
                diag.icd_code LIKE '414%'
            ))
            OR
            -- ICD-10 codes for Ischemic Heart Disease/ACS
            (diag.icd_version = 10 AND (
                diag.icd_code LIKE 'I20%' OR
                diag.icd_code LIKE 'I21%' OR
                diag.icd_code LIKE 'I22%' OR
                diag.icd_code LIKE 'I23%' OR
                diag.icd_code LIKE 'I24%' OR
                diag.icd_code LIKE 'I25%'
            ))
        )
) AS filtered_admissions;