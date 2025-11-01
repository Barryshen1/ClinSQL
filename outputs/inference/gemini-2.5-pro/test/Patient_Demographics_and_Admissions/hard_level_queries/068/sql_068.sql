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
WHERE
    -- Patient criteria
    pat.gender = 'M'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 43 AND 53

    -- Admission criteria
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'SKILLED NURSING FACILITY'

    -- Principal diagnosis criteria
    AND dx.seq_num = 1
    AND dx.icd_code IN ('27651', 'E860') -- ICD-9 and ICD-10 codes for Dehydration;