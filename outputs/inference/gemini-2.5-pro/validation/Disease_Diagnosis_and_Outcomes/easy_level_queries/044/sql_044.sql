SELECT
    AVG(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS average_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
WHERE
    -- 1. Filter for female patients
    pat.gender = 'F'
    -- 2. Filter for patients aged 61-71 at the time of admission
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 61 AND 71
    -- 3. Filter for primary diagnoses only
    AND dx.seq_num = 1
    -- 4. Filter for heart failure diagnoses using both ICD-9 and ICD-10 codes
    AND (
        (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
        OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
    );