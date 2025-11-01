SELECT
    COUNT(DISTINCT a.hadm_id)
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 46 AND 56
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'TRANSFER FROM OTHER HEAL FAC'
    AND di.seq_num = 1 -- Principal diagnosis
    AND di.icd_version = 10 -- Ensuring ICD-10 codes for hip fracture
    AND (
        di.icd_code LIKE 'S72.0%' OR -- Fracture of neck of femur
        di.icd_code LIKE 'S72.1%' OR -- Trochanteric fracture
        di.icd_code LIKE 'S72.2%'    -- Subtrochanteric fracture
    )
;