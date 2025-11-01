SELECT COUNT(DISTINCT adm.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 72 AND 82
    AND adm.insurance = 'Medicare'
    AND adm.admission_type = 'TRANSFER FROM ANOTHER HOSPITAL'
    AND adm.dischtime IS NOT NULL
    AND diag.seq_num = 1
    AND d.long_title LIKE '%unstable angina%';