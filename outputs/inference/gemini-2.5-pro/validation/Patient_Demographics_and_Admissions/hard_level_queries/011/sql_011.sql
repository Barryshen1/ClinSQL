SELECT
    COUNT(DISTINCT adm.hadm_id) AS number_of_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
WHERE
    -- Patient demographic criteria
    pat.gender = 'F'
    AND ( (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age ) BETWEEN 68 AND 78

    -- Admission-level criteria
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.dischtime IS NOT NULL

    -- Clinical criteria: principal diagnosis of hemorrhagic stroke
    AND diag.seq_num = 1
    AND (
        (diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) IN ('430', '431', '432'))
        OR
        (diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
    );