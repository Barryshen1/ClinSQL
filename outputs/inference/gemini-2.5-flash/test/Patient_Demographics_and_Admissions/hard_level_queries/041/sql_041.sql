SELECT
    COUNT(DISTINCT adm.hadm_id)
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 80 AND 90
    AND adm.insurance = 'Medicare'
    AND adm.admission_type = 'EMERGENCY'
    AND diag.seq_num = 1 -- Principal diagnosis
    AND (
        (diag.icd_version = 10 AND STARTS_WITH(diag.icd_code, 'M86')) -- ICD-10 codes for Osteomyelitis
        OR
        (diag.icd_version = 9 AND STARTS_WITH(diag.icd_code, '730')) -- ICD-9 codes for Osteomyelitis
    );