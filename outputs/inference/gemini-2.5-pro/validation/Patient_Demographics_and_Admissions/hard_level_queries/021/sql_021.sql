SELECT
    COUNT(DISTINCT adm.hadm_id) AS number_of_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
WHERE
    -- Patient criteria
    pat.gender = 'F'
    AND adm.insurance = 'Medicare'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 82 AND 92

    -- Admission criteria
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.dischtime IS NOT NULL

    -- Diagnosis criteria (principal diagnosis of acute pancreatitis)
    AND dx.seq_num = 1
    AND (
        (dx.icd_version = 9 AND dx.icd_code = '5770')
        OR (dx.icd_version = 10 AND dx.icd_code LIKE 'K85%')
    );