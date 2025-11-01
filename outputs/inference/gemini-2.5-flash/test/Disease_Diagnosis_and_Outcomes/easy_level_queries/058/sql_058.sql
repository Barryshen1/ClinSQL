SELECT
    -- Calculate the 75th percentile of hospital length of stay in hours
    -- using APPROX_QUANTILES, which is supported in BigQuery.
    -- APPROX_QUANTILES(value, 100)[OFFSET(75)] gets the 75th percentile.
    APPROX_QUANTILES(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR), 100)[OFFSET(75)] AS los_75th_percentile_hours
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dia
    ON adm.hadm_id = dia.hadm_id
WHERE
    -- Filter for female patients
    pat.gender = 'F'
    -- Filter for estimated age at admission between 37 and 47
    -- Calculate age at admission by adding the difference in years between admittime and anchor_year to anchor_age
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 37 AND 47
    -- Filter for primary diagnosis (sequential number 1)
    AND dia.seq_num = 1
    -- Filter for hemorrhagic stroke ICD codes
    -- ICD-9 codes: 430% (Subarachnoid hemorrhage), 431% (Intracerebral hemorrhage)
    -- ICD-10 codes: I60% (Subarachnoid hemorrhage), I61% (Intracerebral hemorrhage)
    AND (
        (dia.icd_version = 9 AND (dia.icd_code LIKE '430%' OR dia.icd_code LIKE '431%'))
        OR
        (dia.icd_version = 10 AND (dia.icd_code LIKE 'I60%' OR dia.icd_code LIKE 'I61%'))
    )
    -- Ensure valid admission and discharge times for LOS calculation
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
    AND adm.dischtime > adm.admittime
;