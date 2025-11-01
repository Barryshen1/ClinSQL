WITH first_24hr_temps AS (
  -- Step 1: Select temperature measurements from the first 24 hours of each ICU stay
  -- and standardize all values to Celsius.
  SELECT
    ie.stay_id,
    ie.subject_id,
    ie.intime,
    CASE
      WHEN ce.itemid = 223761 -- Temperature Fahrenheit
      THEN (ce.valuenum - 32) * 5 / 9
      ELSE ce.valuenum -- Assumes others are Celsius, primarily itemid 223762
    END AS temp_celsius
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ie
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ie.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (
      223762, -- Temperature Celsius
      223761  -- Temperature Fahrenheit
    )
    AND ce.charttime >= ie.intime
    AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),
avg_temp_per_stay AS (
  -- Step 2: Calculate the average temperature for each stay, filtering for plausible values.
  SELECT
    stay_id,
    subject_id,
    intime,
    AVG(temp_celsius) AS avg_temp_c
  FROM
    first_24hr_temps
  WHERE
    temp_celsius BETWEEN 32 AND 43 -- Filter for physiologically plausible temperatures
  GROUP BY
    stay_id,
    subject_id,
    intime
),
population_avg_temps AS (
  -- Step 3: Filter for the target population: male patients aged 82-92 at admission.
  SELECT
    atps.avg_temp_c
  FROM
    avg_temp_per_stay AS atps
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON atps.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    -- Calculate age at the time of ICU admission
    AND (p.anchor_age + EXTRACT(YEAR FROM atps.intime) - p.anchor_year) BETWEEN 82 AND 92
)
-- Step 4: Calculate the percentile rank of 37.5°C for the target population.
-- This is the cumulative distribution: the proportion of stays with an average temp <= 37.5°C.
SELECT
  100.0 * (
    (
      SELECT
        COUNT(*)
      FROM
        population_avg_temps
      WHERE
        avg_temp_c <= 37.5
    ) / (
      SELECT
        COUNT(*)
      FROM
        population_avg_temps
    )
  ) AS percentile_of_37_5_celsius;