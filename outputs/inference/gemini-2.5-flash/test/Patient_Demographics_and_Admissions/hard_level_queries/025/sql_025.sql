SELECT
    COUNT(DISTINCT adm.hadm_id) AS num_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
WHERE
    pat.gender = 'F' -- Female patients
    AND adm.insurance = 'Medicare' -- Medicare patients
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 65 AND 75 -- Aged 65-75 at admission
    AND adm.admission_type = 'TRANSFER' -- Admitted as transfers
    AND adm.admission_location = 'TRANSFER FROM OTHER HOSPITAL' -- Specifically from another hospital
    AND diag.seq_num = 1 -- Principal diagnosis
    AND (
           (diag.icd_version = 9 AND diag.icd_code LIKE '428%') -- ICD-9 codes for Heart Failure (e.g., 428.x)
        OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%') -- ICD-10 codes for Heart Failure (e.g., I50.x)
    )
;