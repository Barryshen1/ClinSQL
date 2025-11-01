WITH map_measurements AS (
  -- Step 1: Select all MAP measurements for the target population within the first 48 hours of their ICU stay.
  SELECT
    icu.stay_id,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  WHERE
    -- Filter for male patients aged 83-93
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 83 AND 93
    -- Filter for MAP itemids (both invasive and non-invasive)
    AND ce.itemid IN (
      220052, -- Arterial Blood Pressure mean
      220181, -- Non Invasive Blood Pressure mean
      225312  -- ART BP mean
    )
    -- Filter for measurements within the first 48 hours of the ICU stay
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
    -- Ensure the value is a valid number
    AND ce.valuenum IS NOT NULL AND ce.valuenum > 0
),

per_stay_avg_map AS (
  -- Step 2: Calculate the average MAP for each stay, filtering for stays with at least 3 measurements.
  SELECT
    stay_id,
    AVG(valuenum) AS avg_map
  FROM
    map_measurements
  GROUP BY
    stay_id
  HAVING
    COUNT(valuenum) >= 3
)

-- Step 3: Calculate the percentile of an average MAP of 60 mmHg among the cohort.
-- This is the percentage of stays with an average MAP less than or equal to 60.
SELECT
  (COUNTIF(avg_map <= 60) / COUNT(*)) * 100 AS percentile_of_60_mmhg
FROM
  per_stay_avg_map;