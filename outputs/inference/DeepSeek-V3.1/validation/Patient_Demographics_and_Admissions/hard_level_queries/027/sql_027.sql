SELECT COUNT(DISTINCT adm.hadm_id) AS admission_count
FROM `physionet-data.mimiciv_3_1_hosp.patients` pt
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pt.subject_id = adm.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 70 AND 80
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND diag.seq_num = 1
    AND diag.icd_code IN (
        '577.0',  -- ICD-9
        'K85.0', 'K85.1', 'K85.2', 'K85.3', 'K85.8', 'K85.9'  -- ICD-10
    );