SELECT COUNT(DISTINCT adm.hadm_id) AS admission_count
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 79 AND 89
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.insurance = 'Medicare'
    AND diag.seq_num = 1
    AND diag.icd_version = 10
    AND diag.icd_code LIKE 'J18%';