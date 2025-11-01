WITH
  cohort_stays AS (
    -- Step 1: Identify ICU stays for female patients aged 58-68
    SELECT
      icu.stay_id,
      icu.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      AND (
        pat.anchor_age + DATETIME_DIFF(icu.intime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR)
      ) BETWEEN 58 AND 68
  ),
  map_events AS (
    -- Step 2: Get all MAP measurements within the first 48 hours for the cohort
    SELECT
      cs.stay_id,
      ce.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN cohort_stays AS cs
      ON ce.stay_id = cs.stay_id
    WHERE
      ce.itemid IN (
        220052, -- Arterial Blood Pressure mean
        225312, -- ART BP mean
        220181  -- Non Invasive Blood Pressure mean
      )
      AND ce.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
      AND ce.valuenum IS NOT NULL
      AND ce.valuenum > 0 -- Basic data cleaning
  ),
  stay_mean_map AS (
    -- Step 3: Calculate the mean MAP for each stay
    SELECT
      stay_id,
      AVG(valuenum) AS mean_map_48hr
    FROM map_events
    GROUP BY
      stay_id
  )
-- Step 4: Calculate the percentile of a mean MAP of 85 mmHg
SELECT
  -- Count of all stays in the cohort with at least one MAP measurement
  COUNT(stay_id) AS total_stays_in_cohort,
  -- Count of stays with a mean MAP at or below the target value
  COUNTIF(mean_map_48hr <= 85) AS stays_at_or_below_85,
  -- Calculate the percentile
  SAFE_DIVIDE(COUNTIF(mean_map_48hr <= 85), COUNT(stay_id)) * 100 AS percentile_of_85_mmhg
FROM stay_mean_map;