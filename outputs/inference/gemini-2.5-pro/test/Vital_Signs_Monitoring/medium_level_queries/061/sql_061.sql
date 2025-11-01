WITH map_events AS (
  -- Step 1: Select all MAP measurements from chartevents for ICU stays.
  -- We include both invasive and non-invasive MAP itemids.
  SELECT
    stay_id,
    valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid IN (
      220052, -- Arterial Blood Pressure mean
      220181, -- Non Invasive Blood Pressure mean
      225312  -- ART BP mean
    )
    AND valuenum IS NOT NULL
    AND valuenum > 0 AND valuenum < 300 -- Basic data cleaning for plausible values
),
avg_map_per_stay AS (
  -- Step 2: Calculate the average MAP for each unique ICU stay.
  SELECT
    stay_id,
    AVG(valuenum) AS avg_map
  FROM
    map_events
  GROUP BY
    stay_id
),
filtered_population AS (
  -- Step 3: Filter for the specific population: male ICU patients aged 38-48.
  SELECT
    map.avg_map
  FROM
    avg_map_per_stay AS map
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON map.stay_id = icu.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 38 AND 48
)
-- Step 4: Calculate the percentile rank for an average MAP of 60 mmHg.
-- This is the proportion of stays with an average MAP <= 60.
SELECT
  100 * COUNTIF(avg_map <= 60) / COUNT(avg_map) AS percentile_rank_for_map_60
FROM
  filtered_population;