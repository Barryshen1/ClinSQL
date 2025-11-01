SELECT COUNT(DISTINCT adm.hadm_id) AS count_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 85 AND 95
    AND adm.insurance = 'Medicare'
    AND adm.admission_location LIKE '%Transfer%Hospital%'
    AND diag.seq_num = 1
    AND diag.icd_code LIKE 'M86%';