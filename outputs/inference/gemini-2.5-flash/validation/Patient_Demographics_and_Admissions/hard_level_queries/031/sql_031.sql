SELECT
    COUNT(DISTINCT adm.hadm_id) AS total_index_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp`.admissions AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS dicd
    ON adm.subject_id = dicd.subject_id AND adm.hadm_id = dicd.hadm_id
WHERE
    pat.gender = 'F'
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND dicd.seq_num = 1 -- Principal diagnosis
    AND (
        (dicd.icd_version = 9 AND dicd.icd_code = '7802') -- ICD-9 for Syncope
        OR
        (dicd.icd_version = 10 AND dicd.icd_code = 'R55') -- ICD-10 for Syncope
    )
    AND (
        pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 62 AND 72
    );