WITH patient_cohort AS (
    -- Step 1: Identify eligible female patients aged 37-47
    SELECT
        p.subject_id,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 37 AND 47
),
icu_stays_filtered AS (
    -- Step 2: Link eligible patients to their ICU stays
    SELECT
        pc.subject_id,
        ic.stay_id
    FROM
        patient_cohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ic
        ON pc.subject_id = ic.subject_id
),
temperature_measurements AS (
    -- Step 3 & 4: Extract temperature measurements and standardize to Celsius
    SELECT
        isf.stay_id,
        -- Standardize temperature to Celsius
        CASE
            WHEN ce.itemid = 223761 THEN ce.valuenum -- Already in Celsius
            WHEN ce.itemid = 220210 THEN (ce.valuenum - 32) * 5 / 9 -- Convert Fahrenheit to Celsius
            ELSE NULL
        END AS temp_celsius
    FROM
        icu_stays_filtered isf
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON isf.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (223761, 220210) -- Filter for Temperature C and Temperature F itemids
        AND ce.valuenum IS NOT NULL -- Ensure a numeric value exists
        -- Filter out physiologically implausible temperature values
        AND (
            (ce.itemid = 223761 AND ce.valuenum BETWEEN 25 AND 45) OR -- Reasonable range for Celsius
            (ce.itemid = 220210 AND ce.valuenum BETWEEN 77 AND 113)    -- Reasonable range for Fahrenheit
        )
),
mean_temp_per_stay AS (
    -- Step 5: Calculate the mean temperature for each ICU stay
    SELECT
        stay_id,
        AVG(temp_celsius) AS mean_temperature_celsius
    FROM
        temperature_measurements
    GROUP BY
        stay_id
    HAVING
        AVG(temp_celsius) IS NOT NULL -- Exclude stays where all temperature values were invalid
)
-- Step 6: Calculate the 75th percentile of these mean temperatures
SELECT
    APPROX_QUANTILES(mean_temperature_celsius, 100)[OFFSET(75)] AS p75_mean_temperature_celsius
FROM
    mean_temp_per_stay;