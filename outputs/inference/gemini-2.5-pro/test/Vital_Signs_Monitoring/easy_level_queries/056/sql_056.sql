WITH first_24hr_temps AS (
  SELECT
    -- Convert Celsius to Fahrenheit for a unified unit, keep Fahrenheit as is
    CASE
      WHEN ce.itemid = 223761 THEN ce.valuenum -- Temperature Fahrenheit
      WHEN ce.itemid = 223762 THEN ce.valuenum * 9/5 + 32 -- Temperature Celsius
    END AS temperature_f
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  WHERE
    -- 1. Filter for the patient cohort: male, age 46-56
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 46 AND 56
    -- 2. Filter for temperature measurements
    AND ce.itemid IN (
      223761, -- Temperature Fahrenheit
      223762  -- Temperature Celsius
    )
    -- 3. Filter for events within the first 24 hours of the ICU stay
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    -- 4. Exclude null or invalid values
    AND ce.valuenum IS NOT NULL AND ce.valuenum > 0
)
-- 5. Calculate the median temperature from the unified values
SELECT
  APPROX_QUANTILES(temperature_f, 2)[OFFSET(1)] AS median_temperature_fahrenheit
FROM
  first_24hr_temps;