SELECT
    COUNT(DISTINCT adm.hadm_id) AS total_index_admissions
FROM
    physionet-data.mimiciv_3_1_hosp.admissions AS adm
INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients AS pat
    ON adm.subject_id = pat.subject_id
INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS dx
    ON adm.hadm_id = dx.hadm_id
INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
WHERE
    -- 1. Patient criteria
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 36 AND 46

    -- 2. Admission criteria
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL'

    -- 3. Principal diagnosis criteria
    AND dx.seq_num = 1
    AND (
        LOWER(d_dx.long_title) LIKE '%hemorrhagic stroke%' OR
        LOWER(d_dx.long_title) LIKE '%intracerebral hemorrhage%' OR
        LOWER(d_dx.long_title) LIKE '%subarachnoid hemorrhage%'
    );