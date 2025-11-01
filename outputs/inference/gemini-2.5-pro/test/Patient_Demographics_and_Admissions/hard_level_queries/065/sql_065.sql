SELECT
    COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
WHERE
    -- Patient criteria
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 72 AND 82

    -- Admission criteria
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
    AND adm.dischtime IS NOT NULL

    -- Principal diagnosis criteria for Unstable Angina (ICD-9 and ICD-10)
    AND dx.seq_num = 1
    AND dx.icd_code IN ('4111', 'I20.0');