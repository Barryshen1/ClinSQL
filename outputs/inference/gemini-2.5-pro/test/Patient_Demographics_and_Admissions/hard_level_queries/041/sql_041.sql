SELECT
    COUNT(DISTINCT adm.hadm_id) AS number_of_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code
    AND dx.icd_version = d_dx.icd_version
WHERE
    -- 1. Filter for female patients aged 80-90 at the time of admission
    pat.gender = 'F'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 80 AND 90

    -- 2. Filter for Medicare patients admitted via the Emergency Department
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY ROOM'

    -- 3. Filter for a principal diagnosis (seq_num = 1) of osteomyelitis
    AND dx.seq_num = 1
    AND LOWER(d_dx.long_title) LIKE '%osteomyelitis%';