SELECT
    COUNT(DISTINCT adm.hadm_id) AS number_of_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 90 AND 100
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'TRANSFER FROM OTHER HEAL/CARE FACILITY'
    AND diag.seq_num = 1 -- Principal diagnosis
    AND diag.icd_code IN ('5856', 'N186') -- ICD-9 585.6 or ICD-10 N18.6 (ESRD);