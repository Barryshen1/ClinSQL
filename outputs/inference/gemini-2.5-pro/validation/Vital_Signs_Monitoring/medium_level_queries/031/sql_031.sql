WITH cohort AS (
    -- Step 1: Identify male ICU stays for patients aged 67-77
    SELECT
        icu.stay_id,
        icu.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON icu.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        -- Calculate age at ICU admission and filter
        AND (
            pat.anchor_age + DATETIME_DIFF(icu.intime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR)
        ) BETWEEN 67 AND 77
),
temps_in_first_24h AS (
    -- Step 2 & 3: Get all temperature readings in the first 24h, convert to Celsius, and clean
    SELECT
        c.stay_id,
        CASE
            -- itemid 223761 is Temperature Fahrenheit
            WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5 / 9
            -- itemid 223762 is Temperature Celsius
            WHEN ce.itemid = 223762 THEN ce.valuenum
            ELSE NULL
        END AS temp_c
    FROM cohort AS c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON c.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (223761, 223762) -- Temperature F and C
        AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
        AND ce.valuenum IS NOT NULL
),
filtered_temps AS (
    -- Further cleaning for physiologically plausible temperatures
    SELECT
        stay_id,
        temp_c
    FROM temps_in_first_24h
    WHERE
        temp_c BETWEEN 32 AND 43 -- Plausible range for human body temp in Celsius
),
stay_avg_temps AS (
    -- Step 4: Calculate the average temperature for each stay that has valid measurements
    SELECT
        stay_id,
        AVG(temp_c) AS avg_temp_c
    FROM filtered_temps
    GROUP BY
        stay_id
)
-- Step 5: Calculate the percentile of 36.0°C among the distribution of average temperatures
SELECT
    (COUNTIF(avg_temp_c <= 36.0) * 100.0) / COUNT(stay_id) AS percentile_of_36_0_c
FROM stay_avg_temps;