WITH

-- Step 1: Identify ICU stays for female patients aged 56-66
cohort AS (
  SELECT
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND (pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) BETWEEN 56 AND 66
),

-- Step 2: Get all MAP measurements for the cohort within the first 48 hours
map_measurements AS (
  SELECT
    ch.stay_id,
    ch.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ch
  INNER JOIN cohort
    ON ch.stay_id = cohort.stay_id
  WHERE
    -- Select itemids for both invasive and non-invasive Mean Arterial Pressure
    ch.itemid IN (
      220052, -- Arterial Blood Pressure mean
      220181, -- Non Invasive Blood Pressure mean
      225312  -- ART BP mean
    )
    -- Filter to the first 48 hours of the ICU stay
    AND ch.charttime BETWEEN cohort.intime AND DATETIME_ADD(cohort.intime, INTERVAL 48 HOUR)
    -- Ensure the value is a plausible number for MAP in mmHg
    AND ch.valuenum IS NOT NULL AND ch.valuenum > 0 AND ch.valuenum < 300
),

-- Step 3: Calculate the mean MAP for each stay over the 48-hour period
stay_mean_map AS (
  SELECT
    stay_id,
    AVG(valuenum) AS mean_map_48hr
  FROM map_measurements
  GROUP BY
    stay_id
),

-- Step 4: Categorize each stay based on its mean MAP
categorized_stays AS (
  SELECT
    mean_map_48hr,
    CASE
      WHEN mean_map_48hr < 65 THEN '<65'
      WHEN mean_map_48hr < 75 THEN '65-74'
      WHEN mean_map_48hr < 85 THEN '75-84'
      ELSE '>=85'
    END AS map_category
  FROM stay_mean_map
)

-- Step 5: Calculate final aggregate statistics for each category
SELECT
  map_category,
  COUNT(mean_map_48hr) AS number_of_stays,
  AVG(mean_map_48hr) AS mean_of_mean_map,
  -- Use APPROX_QUANTILES to find the median (50th percentile)
  APPROX_QUANTILES(mean_map_48hr, 100)[OFFSET(50)] AS median_of_mean_map,
  -- Calculate IQR as the 75th percentile minus the 25th percentile
  (APPROX_QUANTILES(mean_map_48hr, 100)[OFFSET(75)] - APPROX_QUANTILES(mean_map_48hr, 100)[OFFSET(25)]) AS iqr_of_mean_map
FROM categorized_stays
GROUP BY
  map_category
-- Order the results logically by the MAP category, not alphabetically
ORDER BY
  CASE
    WHEN map_category = '<65' THEN 1
    WHEN map_category = '65-74' THEN 2
    WHEN map_category = '75-84' THEN 3
    WHEN map_category = '>=85' THEN 4
  END;