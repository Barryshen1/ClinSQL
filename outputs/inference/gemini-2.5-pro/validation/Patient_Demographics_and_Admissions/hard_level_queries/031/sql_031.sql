SELECT
    COUNT(DISTINCT adm.hadm_id) AS total_index_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
WHERE
    -- 1. Patient criteria: Female, aged 62-72
    pat.gender = 'F'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 62 AND 72

    -- 2. Admission criteria: Medicare, from Emergency Department
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY ROOM'

    -- 3. Diagnosis criteria: Principal diagnosis of Syncope
    AND dx.seq_num = 1 -- Filter for principal diagnosis
    AND (
        (dx.icd_code = '7802' AND dx.icd_version = 9) -- Syncope and collapse (ICD-9)
        OR (dx.icd_code = 'R55' AND dx.icd_version = 10)  -- Syncope and collapse (ICD-10)
    );