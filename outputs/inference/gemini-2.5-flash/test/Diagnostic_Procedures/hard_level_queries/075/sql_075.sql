WITH dka_admissions AS (
    -- Step 1: Identify all unique hospital admissions with a DKA diagnosis
    SELECT DISTINCT
        hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for DKA (250.1x, 250.3x)
        (icd_version = 9 AND (REGEXP_CONTAINS(icd_code, '^250[.]1') OR REGEXP_CONTAINS(icd_code, '^250[.]3')))
        OR
        -- ICD-10 codes for DKA (E10.1x, E11.1x, E13.1x)
        (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, '^E10[.]1') OR REGEXP_CONTAINS(icd_code, '^E11[.]1') OR REGEXP_CONTAINS(icd_code, '^E13[.]1')))
),
filtered_icu_stays_raw AS (
    -- Step 2a: Filter for male ICU admissions aged 39-49 with DKA, calculate LOS and mortality
    -- and assign a row number to identify the first ICU stay per admission
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        -- Calculate ICU Length of Stay in days
        TIMESTAMP_DIFF(icu.outtime, icu.intime, HOUR) / 24.0 AS icu_los_days,
        -- Hospital mortality flag (1 if died in hospital, 0 otherwise)
        adm.hospital_expire_flag AS hospital_mortality_flag,
        -- Assign a row number to find the first ICU stay for each admission
        ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON icu.hadm_id = adm.hadm_id AND icu.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON icu.subject_id = pat.subject_id
    INNER JOIN dka_admissions AS dka
        ON icu.hadm_id = dka.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 39 AND 49
),
filtered_icu_stays AS (
    -- Step 2b: Select only the first ICU stay for each qualifying admission
    SELECT
        subject_id, hadm_id, stay_id, intime, outtime, icu_los_days, hospital_mortality_flag
    FROM filtered_icu_stays_raw
    WHERE rn = 1
),
icu_procedures_24hr AS (
    -- Step 3: Count distinct procedures in the first 24 hours of the *first* ICU stay
    SELECT
        fisu.stay_id,
        COUNT(DISTINCT pe.itemid) AS distinct_procedures_24hr
    FROM filtered_icu_stays AS fisu
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
        ON fisu.stay_id = pe.stay_id
        AND pe.starttime >= fisu.intime
        AND pe.starttime < TIMESTAMP_ADD(fisu.intime, INTERVAL 24 HOUR)
    GROUP BY fisu.stay_id
),
cohort_with_proc_counts AS (
    -- Step 4: Combine filtered ICU stays with their 24-hour procedure counts
    SELECT
        fisu.*,
        COALESCE(ip24.distinct_procedures_24hr, 0) AS distinct_procedures_24hr
    FROM filtered_icu_stays AS fisu
    LEFT JOIN icu_procedures_24hr AS ip24
        ON fisu.stay_id = ip24.stay_id
),
cohort_with_quintiles AS (
    -- Step 5: Assign quintiles based on distinct procedure count
    SELECT
        *,
        NTILE(5) OVER (ORDER BY distinct_procedures_24hr ASC) AS procedure_count_quintile
    FROM cohort_with_proc_counts
)
-- Step 6: Aggregate results by procedure count quintile
SELECT
    procedure_count_quintile,
    COUNT(DISTINCT stay_id) AS num_stays,
    -- Mean, min, max distinct procedure count
    ROUND(AVG(distinct_procedures_24hr), 2) AS mean_procedure_count,
    MIN(distinct_procedures_24hr) AS min_procedure_count,
    MAX(distinct_procedures_24hr) AS max_procedure_count,
    -- Mean ICU LOS in days
    ROUND(AVG(icu_los_days), 2) AS mean_icu_los_days,
    -- Hospital mortality percentage
    ROUND(AVG(hospital_mortality_flag) * 100, 2) AS hospital_mortality_percent
FROM cohort_with_quintiles
GROUP BY procedure_count_quintile
ORDER BY procedure_count_quintile;