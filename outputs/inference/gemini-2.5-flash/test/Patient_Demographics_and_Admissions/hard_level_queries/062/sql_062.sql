SELECT
    COUNT(DISTINCT adm.hadm_id) AS total_index_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
WHERE
    pat.gender = 'F' -- Female patients
    AND pat.anchor_age BETWEEN 38 AND 48 -- Aged 38-48 based on anchor_age
    AND adm.insurance = 'Medicare' -- Medicare patients
    AND adm.admission_location = 'EMERGENCY ROOM' -- Admitted from Emergency Department
    AND diag.seq_num = 1 -- Principal diagnosis
    AND (
           (diag.icd_version = 9 AND diag.icd_code = '5750') -- Acute cholecystitis ICD-9
        OR (diag.icd_version = 10 AND diag.icd_code = 'K810') -- Acute cholecystitis ICD-10
    );