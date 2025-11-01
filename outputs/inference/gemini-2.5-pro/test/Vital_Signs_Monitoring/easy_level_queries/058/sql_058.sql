WITH temp_fahrenheit AS (
  -- Step 1: Select all temperature measurements from chartevents.
  -- Convert Celsius to Fahrenheit to standardize the unit.
  SELECT
    stay_id,
    CASE
      WHEN itemid = 223761 THEN valuenum -- Temperature Fahrenheit
      WHEN itemid = 223762 THEN valuenum * 9 / 5 + 32 -- Temperature Celsius
    END AS temperature_f
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid IN (
      223761, -- Temperature Fahrenheit
      223762  -- Temperature Celsius
    )
    AND valuenum IS NOT NULL
),
min_temp_per_stay AS (
  -- Step 2: Calculate the minimum temperature for each ICU stay.
  -- A physiological range filter is applied to remove erroneous values.
  SELECT
    stay_id,
    MIN(temperature_f) AS min_temp_f
  FROM
    temp_fahrenheit
  WHERE
    temperature_f BETWEEN 77 AND 113 -- Equivalent to ~25-45 Celsius
  GROUP BY
    stay_id
)
-- Step 3: Join with patient data to filter for the cohort and calculate the final median.
SELECT
  APPROX_QUANTILES(mt.min_temp_f, 2)[OFFSET(1)] AS median_of_min_stay_temperatures_f
FROM
  min_temp_per_stay AS mt
-- Join with icustays to link stay_id to a subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  ON mt.stay_id = icu.stay_id
-- Join with patients to filter by age and gender
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON icu.subject_id = p.subject_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 74 AND 84;