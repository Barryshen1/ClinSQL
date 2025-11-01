WITH target_pe_admissions AS (
    -- Step 1: Identify all hospital admissions (hadm_id) that have a pulmonary embolism diagnosis
    -- We look for common ICD-10 and ICD-9 codes associated with Pulmonary Embolism.
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-10 codes for Pulmonary Embolism (I26.x)
        (icd_version = 10 AND icd_code LIKE 'I26%') OR
        -- ICD-9 codes for Pulmonary Embolism and Infarction (415.1x)
        (icd_version = 9 AND icd_code LIKE '415.1%')
),
target_icu_cohort_base AS (
    -- Step 2: Identify the specific demographic (male, 79-89) in ICU admissions with a PE diagnosis
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        DATETIME_DIFF(icu.outtime, icu.intime, HOUR) / 24.0 AS icu_los_days,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON icu.hadm_id = adm.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON icu.subject_id = p.subject_id
    INNER JOIN
        target_pe_admissions tpa
        ON icu.hadm_id = tpa.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 79 AND 89
),
dus_items_target_cohort AS (
    -- Step 3a: Gather diagnostic itemids (lab events and procedure events)
    -- for the target cohort within the first 24 hours of their ICU stay.
    -- DUS is defined as the count of distinct itemids from these two sources.

    -- Lab events in the first 24 hours of target ICU stays
    SELECT
        tc.stay_id,
        le.itemid AS diagnostic_item_id
    FROM
        target_icu_cohort_base tc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON tc.subject_id = le.subject_id AND tc.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN tc.intime AND DATETIME_ADD(tc.intime, INTERVAL 24 HOUR)
        AND le.itemid IS NOT NULL -- Ensure itemid exists
    UNION ALL
    -- Procedure events in the first 24 hours of target ICU stays
    SELECT
        tc.stay_id,
        pe.itemid AS diagnostic_item_id
    FROM
        target_icu_cohort_base tc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON tc.subject_id = pe.subject_id AND tc.hadm_id = pe.hadm_id AND tc.stay_id = pe.stay_id
    WHERE
        pe.starttime BETWEEN tc.intime AND DATETIME_ADD(tc.intime, INTERVAL 24 HOUR)
        AND pe.itemid IS NOT NULL -- Ensure itemid exists
),
dus_scores AS (
    -- Step 3b: Count distinct diagnostic items per target ICU stay to get the DUS
    SELECT
        stay_id,
        COUNT(DISTINCT diagnostic_item_id) AS dus_score
    FROM
        dus_items_target_cohort
    GROUP BY
        stay_id
),
target_cohort_with_dus AS (
    -- Step 4: Combine the target patient cohort base information with their DUS
    SELECT
        tc.subject_id,
        tc.hadm_id,
        tc.stay_id,
        tc.intime,
        tc.outtime,
        tc.icu_los_days,
        tc.hospital_expire_flag,
        COALESCE(ds.dus_score, 0) AS dus_score -- Assign 0 if no diagnostic events found for the stay
    FROM
        target_icu_cohort_base tc
    LEFT JOIN
        dus_scores ds
        ON tc.stay_id = ds.stay_id
),
general_icu_population_stats AS (
    -- Step 5: Gather LOS and mortality data for the general ICU population
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        DATETIME_DIFF(icu.outtime, icu.intime, HOUR) / 24.0 AS icu_los_days,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON icu.hadm_id = adm.hadm_id
)
-- Step 6: Final aggregation and comparison of metrics
SELECT
    'Target Cohort (Male, 79-89, PE)' AS cohort,
    COUNT(DISTINCT tcd.subject_id) AS num_patients,
    COUNT(DISTINCT tcd.stay_id) AS num_icu_stays,
    APPROX_QUANTILES(tcd.dus_score, 100)[OFFSET(75)] AS dus_75th_percentile, -- 75th percentile of DUS
    AVG(tcd.icu_los_days) AS avg_icu_los_days,
    SUM(tcd.hospital_expire_flag) / COUNT(DISTINCT tcd.hadm_id) AS in_hospital_mortality_rate
FROM
    target_cohort_with_dus tcd

UNION ALL

SELECT
    'General ICU Population' AS cohort,
    COUNT(DISTINCT gips.subject_id) AS num_patients,
    COUNT(DISTINCT gips.stay_id) AS num_icu_stays,
    NULL AS dus_75th_percentile, -- DUS not calculated/relevant for general population comparison in this context
    AVG(gips.icu_los_days) AS avg_icu_los_days,
    SUM(gips.hospital_expire_flag) / COUNT(DISTINCT gips.hadm_id) AS in_hospital_mortality_rate
FROM
    general_icu_population_stats gips;