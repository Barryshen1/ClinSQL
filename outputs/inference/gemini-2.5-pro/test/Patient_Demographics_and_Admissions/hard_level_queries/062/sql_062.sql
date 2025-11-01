SELECT
    COUNT(DISTINCT adm.hadm_id) AS total_index_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
WHERE
    -- Patient demographic filters
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48

    -- Admission-specific filters
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY ROOM'

    -- Diagnosis filters for principal diagnosis of acute cholecystitis
    AND diag.seq_num = 1
    AND diag.icd_code IN (
        '5750', -- ICD-9 code for Acute cholecystitis
        'K810'  -- ICD-10 code for Acute cholecystitis
    );