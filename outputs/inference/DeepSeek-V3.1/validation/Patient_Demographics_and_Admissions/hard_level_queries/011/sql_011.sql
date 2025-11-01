SELECT COUNT(DISTINCT adm.hadm_id) AS count_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 68 AND 78
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.insurance = 'Medicare'
    AND adm.dischtime IS NOT NULL
    AND diag.seq_num = 1
    AND (
        -- ICD-9: 430, 431, 432.x
        (diag.icd_version = 9 AND REGEXP_CONTAINS(diag.icd_code, r'^(430|431|432)')) OR
        -- ICD-10: I60.x, I61.x, I62.x
        (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^(I60|I61|I62)'))
    );