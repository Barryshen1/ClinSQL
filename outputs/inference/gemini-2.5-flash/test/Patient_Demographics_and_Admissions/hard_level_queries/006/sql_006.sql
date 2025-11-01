SELECT
    COUNT(DISTINCT adm.hadm_id) AS total_index_admissions_in_cohort
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_icd
    ON adm.subject_id = diag_icd.subject_id AND adm.hadm_id = diag_icd.hadm_id
WHERE
    pat.gender = 'F' -- Female patients
    AND pat.anchor_age BETWEEN 36 AND 46 -- Aged 36-46
    AND adm.insurance = 'Medicare' -- Medicare patients
    AND adm.admission_location = 'TRANSFER FROM OTHER HOSPITAL' -- Admitted via transfer
    AND diag_icd.seq_num = 1 -- Principal diagnosis
    AND (
        (diag_icd.icd_version = 9 AND diag_icd.icd_code IN ('430', '431')) -- ICD-9 codes for hemorrhagic stroke
        OR
        (diag_icd.icd_version = 10 AND (diag_icd.icd_code LIKE 'I60%' OR diag_icd.icd_code LIKE 'I61%')) -- ICD-10 codes for hemorrhagic stroke
    );