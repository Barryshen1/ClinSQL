SELECT
    COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
WHERE
    -- 1. Patient demographic filters
    pat.gender = 'F'
    AND adm.insurance = 'Medicare'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 72 AND 82

    -- 2. Admission-specific filters
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.hospital_expire_flag = 0 -- Filter for patients who were discharged alive

    -- 3. Principal diagnosis filter for Acute Pancreatitis
    AND dx.seq_num = 1
    AND (
        -- ICD-9 code for Acute Pancreatitis
        (dx.icd_code = '5770' AND dx.icd_version = 9)
        -- ICD-10 codes for Acute Pancreatitis
        OR (dx.icd_code LIKE 'K85%' AND dx.icd_version = 10)
    );