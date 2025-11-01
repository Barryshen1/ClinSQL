WITH EligiblePatients AS (
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 90 AND 100
),
SepsisAdmissions AS (
    SELECT DISTINCT
        di.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        -- ICD-9 codes for sepsis
        (di.icd_version = 9 AND di.icd_code IN ('99591', '99592', '78552')) OR
        -- ICD-10 codes for sepsis
        (di.icd_version = 10 AND (
            di.icd_code LIKE 'A40%' OR    -- Streptococcal sepsis
            di.icd_code LIKE 'A41%' OR    -- Other sepsis
            di.icd_code IN ('R6520', 'R6521') -- Severe sepsis
        ))
)
SELECT
    STDDEV(icu.los) AS stddev_icu_los_days
FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
JOIN
    EligiblePatients ep
    ON icu.subject_id = ep.subject_id
JOIN
    SepsisAdmissions sa
    ON icu.hadm_id = sa.hadm_id;