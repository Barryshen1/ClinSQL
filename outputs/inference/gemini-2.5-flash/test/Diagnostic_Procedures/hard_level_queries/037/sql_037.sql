WITH base_cohort AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        icustay.stay_id,
        icustay.intime,
        icustay.los AS icu_los,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icustay
        ON adm.hadm_id = icustay.hadm_id AND p.subject_id = icustay.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 53 AND 63
),
-- Step 2: Identify sepsis diagnoses within the base cohort
-- Using common ICD-10 codes for sepsis.
sepsis_cohort_stays AS (
    SELECT DISTINCT
        bc.stay_id
    FROM
        base_cohort AS bc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON bc.hadm_id = di.hadm_id AND bc.subject_id = di.subject_id
    WHERE
        di.icd_version = 10 AND (
            di.icd_code LIKE 'A40%' OR  -- Streptococcal sepsis, etc.
            di.icd_code LIKE 'A41%' OR  -- Other sepsis, including gram-negative, unspecified, etc.
            di.icd_code LIKE 'R65.2%'   -- Severe sepsis (R65.20 without shock, R65.21 with shock)
        )
),
-- Step 3: Count procedures in the first 24 hours of ICU stay for the base cohort
procedures_24h_counts AS (
    SELECT
        bc.stay_id,
        COUNT(pe.itemid) AS procedure_count_24h -- Count each recorded procedure event
    FROM
        base_cohort AS bc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
        ON bc.stay_id = pe.stay_id
    WHERE
        pe.starttime >= bc.intime
        AND pe.starttime < TIMESTAMP_ADD(bc.intime, INTERVAL 24 HOUR)
    GROUP BY
        bc.stay_id
),
-- Step 4: Combine all data and add cohort flags
final_cohort_data AS (
    SELECT
        bc.subject_id,
        bc.hadm_id,
        bc.stay_id,
        bc.intime,
        bc.icu_los,
        bc.hospital_expire_flag,
        CASE
            WHEN scs.stay_id IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS is_sepsis_cohort_flag,
        COALESCE(p24.procedure_count_24h, 0) AS procedure_count_24h -- Default to 0 if no procedures
    FROM
        base_cohort AS bc
    LEFT JOIN
        sepsis_cohort_stays AS scs
        ON bc.stay_id = scs.stay_id
    LEFT JOIN
        procedures_24h_counts AS p24
        ON bc.stay_id = p24.stay_id
)
-- Step 5: Calculate and compare metrics for both cohorts
-- Cohort 1: Sepsis Cohort (Female, 53-63)
SELECT
    'Sepsis Cohort (Female, 53-63)' AS cohort_name,
    APPROX_QUANTILES(procedure_count_24h, 100)[OFFSET(75)] AS procedures_24h_75th_percentile,
    APPROX_QUANTILES(procedure_count_24h, 100)[OFFSET(90)] AS procedures_24h_90th_percentile,
    AVG(icu_los) AS average_icu_los,
    AVG(hospital_expire_flag) * 100 AS hospital_mortality_rate_percent -- Hospital mortality as percentage
FROM
    final_cohort_data
WHERE
    is_sepsis_cohort_flag = TRUE

UNION ALL

-- Cohort 2: Age-Matched Control Cohort (Female, 53-63, All ICU patients)
-- This includes all female ICU patients aged 53-63, regardless of sepsis status, for comparison.
SELECT
    'Age-Matched Control Cohort (Female, 53-63, All ICU patients)' AS cohort_name,
    APPROX_QUANTILES(procedure_count_24h, 100)[OFFSET(75)] AS procedures_24h_75th_percentile,
    APPROX_QUANTILES(procedure_count_24h, 100)[OFFSET(90)] AS procedures_24h_90th_percentile,
    AVG(icu_los) AS average_icu_los,
    AVG(hospital_expire_flag) * 100 AS hospital_mortality_rate_percent -- Hospital mortality as percentage
FROM
    final_cohort_data
WHERE hospital_expire_flag IS NOT NULL -- Ensure only patients with known mortality status are included
;