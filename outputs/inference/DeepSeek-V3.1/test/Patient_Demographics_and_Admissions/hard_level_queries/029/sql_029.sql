SELECT COUNT(DISTINCT adm.hadm_id) AS count_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 46 AND 56
    AND adm.admission_type = 'TRANSFER FROM ANOTHER HOSPITAL'
    AND diag.seq_num = 1
    AND (
        (diag.icd_version = 10 AND diag.icd_code LIKE 'S72%')
        OR (diag.icd_version = 9 AND diag.icd_code LIKE '820%')
    );