WITH filtered_stays AS (
  -- First, identify the cohort of female ICU patients aged 37-47
  SELECT
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND (
      -- Calculate age at the time of ICU admission
      pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year
    ) BETWEEN 37 AND 47
),
temperatures AS (
  -- Next, gather all temperature measurements for these stays, converting to Celsius
  SELECT
    ce.stay_id,
    CASE
      WHEN ce.itemid = 223761
        THEN (ce.valuenum - 32) * 5 / 9 -- Convert Fahrenheit to Celsius
      WHEN ce.itemid = 223762
        THEN ce.valuenum -- Already in Celsius
    END AS temp_celsius
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  INNER JOIN
    filtered_stays AS fs
    ON ce.stay_id = fs.stay_id
  WHERE
    ce.valuenum IS NOT NULL
    -- Filter for relevant itemids and plausible physiological values
    AND (
      (ce.itemid = 223762 AND ce.valuenum BETWEEN 30 AND 43) -- Celsius
      OR (ce.itemid = 223761 AND ce.valuenum BETWEEN 86 AND 110) -- Fahrenheit
    )
),
stay_mean_temps AS (
  -- Then, calculate the mean temperature for each stay
  SELECT
    stay_id,
    AVG(temp_celsius) AS mean_temp_per_stay
  FROM
    temperatures
  GROUP BY
    stay_id
)
-- Finally, calculate the 75th percentile of the mean temperatures across all stays
SELECT
  APPROX_QUANTILES(mean_temp_per_stay, 100)[OFFSET(75)] AS p75_mean_temperature_celsius
FROM
  stay_mean_temps;