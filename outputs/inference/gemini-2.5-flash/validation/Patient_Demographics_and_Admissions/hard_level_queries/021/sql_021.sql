SELECT
    COUNT(DISTINCT adm.hadm_id) AS num_admissions
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
    AND pat.anchor_age BETWEEN 82 AND 92
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.dischtime IS NOT NULL
    AND diag.seq_num = 1 -- Principal diagnosis
    AND (
        diag.icd_code = '5770' -- ICD-9 for Acute Pancreatitis
        OR STARTS_WITH(diag.icd_code, 'K85') -- ICD-10 for Acute Pancreatitis
    );