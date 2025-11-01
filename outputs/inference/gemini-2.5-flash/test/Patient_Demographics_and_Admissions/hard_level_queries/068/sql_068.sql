SELECT
    COUNT(DISTINCT adm.hadm_id) AS number_of_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
    ON diag.icd_code = d_diag.icd_code
    AND diag.icd_version = d_diag.icd_version
WHERE
    p.gender = 'M' -- Male patients
    AND p.anchor_age BETWEEN 43 AND 53 -- Aged 43-53
    AND adm.insurance = 'Medicare' -- Medicare patients
    AND adm.admission_location = 'SKILLED NURSING FACILITY' -- Admitted from SNF
    AND diag.seq_num = 1 -- Principal diagnosis
    AND (
        d_diag.long_title LIKE '%Dehydration%' -- Diagnosis description contains 'Dehydration'
        OR diag.icd_code IN ('E860', '27651') -- Specific ICD codes for dehydration (ICD-10 E86.0 and ICD-9 276.51)
    );