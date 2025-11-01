SELECT
    COUNT(DISTINCT adm.hadm_id) AS number_of_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
WHERE
    pat.gender = 'F' -- Female patients
    AND pat.anchor_age BETWEEN 85 AND 95 -- Aged 85 to 95
    AND adm.insurance = 'Medicare' -- Medicare patients
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL' -- Transferred from another hospital
    AND diag.seq_num = 1 -- Principal diagnosis
    AND d_diag.long_title LIKE '%osteomyelitis%'; -- Diagnosis of osteomyelitis;