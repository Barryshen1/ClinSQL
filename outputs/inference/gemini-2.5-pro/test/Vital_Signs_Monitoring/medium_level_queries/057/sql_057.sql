WITH stay_cohort AS (
  -- Step 1: Identify the target cohort of ICU stays for male patients aged 85-95.
  SELECT
    i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
),

temperatures AS (
  -- Step 2: Extract temperature measurements and standardize them to Celsius.
  SELECT
    stay_id,
    CASE
      WHEN itemid = 223761 -- Temperature Fahrenheit
      THEN (valuenum - 32) * 5 / 9
      WHEN itemid = 223762 -- Temperature Celsius
      THEN valuenum
      ELSE NULL
    END AS temp_celsius
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid IN (223761, 223762)
),

stay_avg_temps AS (
  -- Step 3: Calculate the average temperature for each stay in the cohort.
  SELECT
    sc.stay_id,
    AVG(t.temp_celsius) AS avg_temp
  FROM stay_cohort AS sc
  INNER JOIN temperatures AS t
    ON sc.stay_id = t.stay_id
  -- Filter for physiologically plausible temperatures to remove outliers.
  WHERE
    t.temp_celsius BETWEEN 25 AND 45
  GROUP BY
    sc.stay_id
)

-- Step 4: Calculate the percentile rank of 36.0°C within the distribution of average temperatures.
-- The percentile rank is the percentage of stays with an average temperature <= 36.0°C.
SELECT
  100.0 * COUNTIF(avg_temp <= 36.0) / COUNT(stay_id) AS percentile_rank_of_36_C
FROM stay_avg_temps;