WITH
  target_icu_stays AS (
    -- Step 1 & 2: Identify male patients aged 40-50 and their ICU stays
    SELECT
      p.subject_id,
      ie.stay_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.icustays` AS ie
      ON p.subject_id = ie.subject_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 40 AND 50
  ),
  stay_heart_rates AS (
    -- Step 3: Get all Heart Rate measurements for these specific ICU stays
    SELECT
      ts.stay_id,
      ce.valuenum AS heart_rate
    FROM
      target_icu_stays AS ts
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ts.stay_id = ce.stay_id
    WHERE
      ce.itemid = 220045 -- ItemID for 'Heart Rate' from d_items (verified)
      AND ce.valuenum IS NOT NULL
      -- Filter out physiologically implausible heart rates to ensure data quality
      AND ce.valuenum > 0
      AND ce.valuenum < 300
  ),
  per_stay_mean_hr AS (
    -- Step 4: Calculate the mean heart rate for each individual ICU stay
    SELECT
      stay_id,
      AVG(heart_rate) AS mean_heart_rate
    FROM
      stay_heart_rates
    GROUP BY
      stay_id
    HAVING
      COUNT(heart_rate) > 0 -- Ensure the stay had at least one valid HR measurement
  )
-- Step 5: Calculate the median of these per-stay mean heart rates
SELECT
  PERCENTILE_CONT(mean_heart_rate, 0.5) OVER() AS median_per_stay_mean_heart_rate
FROM
  per_stay_mean_hr
LIMIT 1; -- Use LIMIT 1 as PERCENTILE_CONT OVER() returns the same value for all rows;