WITH 
-- Step 1: Get heart failure hadm_ids
heart_failure_hadm AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        (icd_version = 9 AND icd_code LIKE '428%')
        OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
-- Step 2: Base ICU stays with demographics and flags
base_stays AS (
    SELECT 
        i.stay_id,
        i.hadm_id,
        i.subject_id,
        i.intime,
        i.los,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        a.hospital_expire_flag,
        -- Compute age at ICU admission
        p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age,
        -- Flag for heart failure
        CASE WHEN hf.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_heart_failure
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.hadm_id = a.hadm_id
    LEFT JOIN heart_failure_hadm hf
        ON i.hadm_id = hf.hadm_id
),
-- Step 3: Diagnostic counts per stay
lab_events_in_window AS (
    SELECT 
        i.stay_id,
        COUNT(*) AS lab_count
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON i.hadm_id = l.hadm_id
        AND l.charttime >= i.intime
        AND l.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
    GROUP BY i.stay_id
),
micro_events_in_window AS (
    SELECT 
        i.stay_id,
        COUNT(*) AS micro_count
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` m
        ON i.hadm_id = m.hadm_id
        AND m.charttime >= i.intime
        AND m.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
    GROUP BY i.stay_id
),
diagnostic_counts AS (
    SELECT 
        i.stay_id,
        COALESCE(l.lab_count, 0) + COALESCE(m.micro_count, 0) AS total_diagnostic
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    LEFT JOIN lab_events_in_window l ON i.stay_id = l.stay_id
    LEFT JOIN micro_events_in_window m ON i.stay_id = m.stay_id
),
-- Step 4: Combine base_stays with diagnostic_counts
stay_data AS (
    SELECT 
        b.*,
        d.total_diagnostic
    FROM base_stays b
    LEFT JOIN diagnostic_counts d
        ON b.stay_id = d.stay_id
)
-- Now compute aggregates for target and general
SELECT 
    'target' AS group_label,
    AVG(total_diagnostic) AS mean_diagnostic,
    APPROX_QUANTILES(total_diagnostic, 1000)[OFFSET(500)] AS median_diagnostic,
    APPROX_QUANTILES(total_diagnostic, 1000)[OFFSET(750)] AS p75_diagnostic,
    APPROX_QUANTILES(total_diagnostic, 1000)[OFFSET(950)] AS p95_diagnostic,
    AVG(los) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate
FROM stay_data
WHERE 
    gender = 'M'
    AND age BETWEEN 70 AND 80
    AND has_heart_failure = 1

UNION ALL

SELECT 
    'general' AS group_label,
    AVG(total_diagnostic) AS mean_diagnostic,
    APPROX_QUANTILES(total_diagnostic, 1000)[OFFSET(500)] AS median_diagnostic,
    APPROX_QUANTILES(total_diagnostic, 1000)[OFFSET(750)] AS p75_diagnostic,
    APPROX_QUANTILES(total_diagnostic, 1000)[OFFSET(950)] AS p95_diagnostic,
    AVG(los) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate
FROM stay_data;