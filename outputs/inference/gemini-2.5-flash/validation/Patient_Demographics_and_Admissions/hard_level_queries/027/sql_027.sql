SELECT
    COUNT(DISTINCT adm.hadm_id) AS num_index_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dicd
    ON adm.subject_id = dicd.subject_id AND adm.hadm_id = dicd.hadm_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddicd
    ON dicd.icd_code = ddicd.icd_code AND dicd.icd_version = ddicd.icd_version
WHERE
    pat.gender = 'F' -- Female patients
    AND adm.insurance = 'Medicare' -- Medicare patients
    AND adm.admission_location = 'EMERGENCY ROOM' -- Admitted from ED
    AND dicd.seq_num = 1 -- Principal diagnosis
    AND LOWER(ddicd.long_title) LIKE '%acute pancreatitis%' -- Diagnosis of acute pancreatitis
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 70 AND 80 -- Aged 70-80 at admission
;