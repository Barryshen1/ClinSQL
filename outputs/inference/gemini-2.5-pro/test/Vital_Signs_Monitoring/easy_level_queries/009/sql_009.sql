WITH temperature_events AS (
  SELECT
    -- Standardize all temperature readings to Fahrenheit
    CASE
      WHEN ce.itemid = 223762 THEN (ce.valuenum * 9 / 5) + 32 -- Convert Celsius to Fahrenheit
      WHEN ce.itemid = 223761 THEN ce.valuenum -- Value is already in Fahrenheit
    END AS temperature_f
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON pat.subject_id = icu.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  WHERE
    -- 1. Filter for the patient cohort: Female, aged 86-96
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 86 AND 96
    -- 2. Filter for temperature measurements
    AND ce.itemid IN (
      223761, -- Temperature Fahrenheit
      223762  -- Temperature Celsius
    )
    -- 3. Filter for the first 24 hours of the ICU stay
    AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    -- 4. Ensure there is a numeric value to process
    AND ce.valuenum IS NOT NULL
)
-- Final calculation of the 75th percentile from the prepared data
SELECT
  APPROX_QUANTILES(temperature_f, 100)[OFFSET(75)] AS percentile_75th_temperature_f
FROM
  temperature_events
WHERE
  -- 5. Add a plausible physiological range filter to exclude erroneous readings
  temperature_f > 80 AND temperature_f < 110;