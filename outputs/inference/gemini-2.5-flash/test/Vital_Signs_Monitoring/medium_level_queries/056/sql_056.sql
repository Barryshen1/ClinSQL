WITH PatientPopulation AS (
    SELECT
        p.subject_id,
        icu.hadm_id,
        icu.stay_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON p.subject_id = icu.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 89 AND 99
),
TemperatureMeasurements AS (
    SELECT
        pp.subject_id,
        pp.hadm_id,
        pp.stay_id,
        ce.charttime,
        -- Convert all temperatures to Celsius for consistent analysis
        CASE
            WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5/9 -- Fahrenheit to Celsius (itemid 223761: Temperature Fahrenheit)
            WHEN ce.itemid = 223762 THEN ce.valuenum             -- Already Celsius (itemid 223762: Temperature C)
            ELSE NULL -- Should not happen with itemid filter that ensures conversion
        END AS temp_celsius
    FROM
        PatientPopulation pp
    JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON pp.subject_id = ce.subject_id
        AND pp.hadm_id = ce.hadm_id
        AND pp.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (223761, 223762) -- Filter for common Temperature F and C itemIDs
        AND ce.valuenum IS NOT NULL -- Ensure a numeric value exists for conversion attempt
),
CategorizedTemperatures AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        charttime,
        temp_celsius,
        CASE
            WHEN temp_celsius < 36 THEN '<36 °C'
            WHEN temp_celsius >= 36 AND temp_celsius < 38 THEN '36-37.9 °C'
            WHEN temp_celsius >= 38 THEN '>=38 °C'
            ELSE 'Unknown'
        END AS temp_category
    FROM TemperatureMeasurements
    WHERE
        temp_celsius IS NOT NULL
        -- Filter for physiologically plausible Celsius values to exclude erroneous readings
        AND temp_celsius BETWEEN 20.0 AND 45.0
),
TotalMeasurements AS (
    SELECT
        COUNT(*) AS total_measurement_count
    FROM CategorizedTemperatures
)
SELECT
    ct.temp_category,
    ROUND(AVG(ct.temp_celsius), 2) AS mean_temperature_c,
    -- FIX: Use BigQuery's APPROX_QUANTILES for median
    ROUND(APPROX_QUANTILES(ct.temp_celsius, 4)[OFFSET(2)], 2) AS median_temperature_c,
    ROUND(
        (APPROX_QUANTILES(ct.temp_celsius, 4)[OFFSET(3)]) - -- FIX: Use BigQuery's APPROX_QUANTILES for Q3
        (APPROX_QUANTILES(ct.temp_celsius, 4)[OFFSET(1)]), 2 -- FIX: Use BigQuery's APPROX_QUANTILES for Q1
    ) AS iqr_temperature_c,
    COUNT(DISTINCT ct.subject_id) AS unique_patient_count,
    COUNT(*) AS measurement_count,
    -- Renaming `measurement_percentage` to `MI_rate` as requested, interpreted as proportion of valid measurements in category.
    ROUND(COUNT(*) * 100.0 / (SELECT total_measurement_count FROM TotalMeasurements), 2) AS MI_rate
FROM
    CategorizedTemperatures ct
GROUP BY
    ct.temp_category
ORDER BY
    CASE
        WHEN ct.temp_category = '<36 °C' THEN 1
        WHEN ct.temp_category = '36-37.9 °C' THEN 2
        WHEN ct.temp_category = '>=38 °C' THEN 3
        ELSE 4
    END;