SELECT
    APPROX_QUANTILES(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY), 100)[OFFSET(75)] AS percentile_75th_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
WHERE
    -- 1. Filter for patient demographics: Males aged 37-47
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 37 AND 47

    -- 2. Filter for primary diagnosis of Acute Kidney Injury (AKI)
    AND dx.seq_num = 1
    AND (
        (dx.icd_version = 9 AND dx.icd_code LIKE '584%') -- AKI codes for ICD-9
        OR
        (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%') -- AKI codes for ICD-10
    );