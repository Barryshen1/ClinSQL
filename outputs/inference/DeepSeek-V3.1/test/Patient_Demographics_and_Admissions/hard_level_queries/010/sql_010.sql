SELECT COUNT(DISTINCT adm.hadm_id) AS admission_count
FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.insurance = 'Medicare'
    AND diag.seq_num = 1
    AND (
        (diag.icd_version = 10 AND diag.icd_code = 'E10.1') 
        OR 
        (diag.icd_version = 9 AND diag.icd_code = '250.13')
    );