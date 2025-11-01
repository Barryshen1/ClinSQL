SELECT COUNT(DISTINCT adm.hadm_id) AS admission_count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.dischtime IS NOT NULL
    AND diag.seq_num = 1
    AND (
        (diag.icd_version = 9 AND diag.icd_code = '577.0') 
        OR 
        (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
    );