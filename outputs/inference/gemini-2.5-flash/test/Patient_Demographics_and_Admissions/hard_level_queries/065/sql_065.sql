SELECT
    COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_icd
    ON adm.subject_id = diag_icd.subject_id AND adm.hadm_id = diag_icd.hadm_id
WHERE
    pat.gender = 'M'
    AND adm.insurance = 'Medicare'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 72 AND 82
    AND adm.admission_location = 'TRANSFER FROM OTHER HOSPITAL'
    AND diag_icd.seq_num = 1 -- Principal diagnosis
    AND (
        (diag_icd.icd_version = 9 AND diag_icd.icd_code = '4111') -- Unstable angina (ICD-9)
        OR (diag_icd.icd_version = 10 AND diag_icd.icd_code = 'I200') -- Unstable angina (ICD-10)
    )
    AND adm.dischtime IS NOT NULL -- Ensure discharge was recorded
;