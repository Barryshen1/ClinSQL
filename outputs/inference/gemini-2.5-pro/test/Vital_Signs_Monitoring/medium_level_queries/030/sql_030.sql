WITH
-- Step 1: Define the patient cohort of female ICU patients aged 81-91
cohort AS (
    SELECT
        p.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 81 AND 91
),

-- Step 2: Extract and standardize temperature readings from the first 24 hours
temps_24h AS (
    SELECT
        c.stay_id,
        -- Convert Fahrenheit to Celsius, otherwise use the value as is.
        CASE
            WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5 / 9
            ELSE ce.valuenum
        END AS temperature_c
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN cohort AS c
        ON ce.stay_id = c.stay_id
    WHERE
        ce.itemid IN (
            223762, -- Temperature Celsius
            223761  -- Temperature Fahrenheit
        )
        AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
        AND ce.valuenum IS NOT NULL
),

-- Step 3: Calculate the mean temperature per stay, filtering for plausible values
mean_temps AS (
    SELECT
        stay_id,
        AVG(temperature_c) AS mean_temp_c
    FROM temps_24h
    -- Filter for physiologically plausible temperatures in Celsius before averaging
    WHERE temperature_c BETWEEN 25 AND 45
    GROUP BY stay_id
),

-- Step 4: Identify hospital admissions with a Myocardial Infarction diagnosis
mi_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for acute MI
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '410')
        -- ICD-10 codes for acute MI
        OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I21')
),

-- Step 5: Consolidate data, flag for MI, and classify temperature
stay_summary AS (
    SELECT
        c.stay_id,
        mt.mean_temp_c,
        -- Create a binary flag for MI diagnosis for the parent admission
        CASE WHEN mi.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_mi,
        -- Classify the mean temperature into the specified groups
        CASE
            WHEN mt.mean_temp_c < 36.0 THEN '<36.0'
            WHEN mt.mean_temp_c >= 36.0 AND mt.mean_temp_c < 38.0 THEN '36.0-37.9'
            WHEN mt.mean_temp_c >= 38.0 THEN '>=38.0'
            ELSE NULL
        END AS temp_group
    FROM cohort AS c
    -- INNER JOIN ensures only stays with valid temperature measurements are included
    INNER JOIN mean_temps AS mt
        ON c.stay_id = mt.stay_id
    -- LEFT JOIN to include all stays from the temperature cohort, regardless of MI status
    LEFT JOIN mi_admissions AS mi
        ON c.hadm_id = mi.hadm_id
)

-- Step 6: Final aggregation and reporting
SELECT
    temp_group,
    COUNT(stay_id) AS N_stays,
    ROUND(AVG(mean_temp_c), 2) AS mean_temperature,
    ROUND(CAST(APPROX_QUANTILES(mean_temp_c, 100)[OFFSET(50)] AS NUMERIC), 2) AS median_temperature,
    ROUND(
        CAST(APPROX_QUANTILES(mean_temp_c, 100)[OFFSET(75)] AS NUMERIC) -
        CAST(APPROX_QUANTILES(mean_temp_c, 100)[OFFSET(25)] AS NUMERIC)
    , 2) AS iqr_temperature,
    ROUND(AVG(has_mi) * 100, 2) AS mi_rate_percent
FROM stay_summary
WHERE temp_group IS NOT NULL
GROUP BY temp_group
ORDER BY
    -- Custom sort order to match the classification logic
    CASE
        WHEN temp_group = '<36.0' THEN 1
        WHEN temp_group = '36.0-37.9' THEN 2
        WHEN temp_group = '>=38.0' THEN 3
    END;