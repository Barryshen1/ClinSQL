SELECT
    STDDEV(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS sd_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
WHERE
    -- 1. Filter for female patients
    pat.gender = 'F'
    -- 2. Filter for patients aged 67-77 at the time of admission
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 67 AND 77
    -- 3. Filter for primary diagnoses
    AND diag.seq_num = 1
    -- 4. Filter for diagnoses of sepsis or septic shock
    AND (
        LOWER(d_icd.long_title) LIKE '%sepsis%'
        OR LOWER(d_icd.long_title) LIKE '%septic shock%'
    );