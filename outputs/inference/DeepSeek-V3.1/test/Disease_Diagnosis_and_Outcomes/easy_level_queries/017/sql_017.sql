SELECT 
    MAX(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS max_los_days
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
WHERE 
    p.anchor_age BETWEEN 84 AND 94
    AND p.gender = 'M'
    AND diag.seq_num = 1
    AND d.icd_code LIKE 'I63%'
    AND diag.icd_version = 10
    AND a.dischtime IS NOT NULL;