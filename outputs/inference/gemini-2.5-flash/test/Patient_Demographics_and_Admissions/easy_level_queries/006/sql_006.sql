WITH SepsisAdmissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for sepsis and severe sepsis
        (
            icd_version = 9 AND icd_code IN ('99591', '99592')
        )
        OR
        -- ICD-10 codes for various types of sepsis and septic shock
        (
            icd_version = 10 AND (
                -- A40: Streptococcal sepsis
                STARTS_WITH(icd_code, 'A40')
                -- A41: Other sepsis
                OR STARTS_WITH(icd_code, 'A41')
                -- R65.2: Severe sepsis, unspecified or septic shock
                OR STARTS_WITH(icd_code, 'R652')
            )
        )
)
-- Main query to calculate the median ICU LOS for the specified cohort
SELECT
    -- Calculate the median of the 'los' (Length of Stay in days) from the filtered ICU stays
    PERCENTILE_CONT(icu.los, 0.5) OVER() AS median_icu_los_days
FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
-- Join with the patients table to filter by gender and age
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
-- Join with the SepsisAdmissions CTE to filter for admissions with a sepsis diagnosis
JOIN
    SepsisAdmissions sa
    ON icu.hadm_id = sa.hadm_id
WHERE
    -- Filter for female patients
    pat.gender = 'F'
    -- Filter for patients aged between 58 and 68 (inclusive)
    AND pat.anchor_age BETWEEN 58 AND 68;