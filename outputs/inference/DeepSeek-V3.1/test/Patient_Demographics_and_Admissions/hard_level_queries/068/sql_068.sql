SELECT COUNT(DISTINCT adm.hadm_id) AS admission_count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND adm.admission_location = 'SKILLED NURSING FACILITY'
    AND adm.insurance = 'Medicare'
    AND diag.seq_num = 1
    AND (
        (diag.icd_version = 10 AND diag.icd_code = 'E860') 
        OR 
        (diag.icd_version = 9 AND diag.icd_code = '27651')
    );