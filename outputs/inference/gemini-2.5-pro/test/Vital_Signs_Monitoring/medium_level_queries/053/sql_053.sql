WITH
  -- Step 1: Identify the cohort of female ICU patients aged 65-75
  cohort AS (
    SELECT
      icu.stay_id,
      icu.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 65 AND 75
  ),
  -- Step 2: Get all systolic BP measurements in the first 24h for the cohort and categorize them
  sbp_events AS (
    SELECT
      ch.valuenum,
      CASE
        WHEN ch.valuenum < 140
        THEN '<140'
        WHEN ch.valuenum >= 140 AND ch.valuenum <= 159
        THEN '140-159'
        WHEN ch.valuenum >= 160
        THEN '>=160'
        ELSE NULL
      END AS bp_category
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ch
    INNER JOIN cohort
      ON ch.stay_id = cohort.stay_id
    WHERE
      -- Filter for systolic blood pressure itemids (non-invasive and invasive)
      ch.itemid IN (220179, 220050)
      -- Filter for the first 24 hours of the ICU stay
      AND ch.charttime BETWEEN cohort.intime AND DATETIME_ADD(
        cohort.intime,
        INTERVAL 24 HOUR
      )
      -- Basic data cleaning for plausible values
      AND ch.valuenum IS NOT NULL
      AND ch.valuenum > 0 AND ch.valuenum < 400
  )
-- Step 3: Group by category and calculate summary statistics
SELECT
  bp_category,
  COUNT(*) AS number_of_measurements,
  ROUND(AVG(valuenum), 2) AS mean_sbp,
  ROUND(APPROX_QUANTILES(valuenum, 100)[OFFSET(50)], 2) AS median_sbp,
  ROUND(
    (
      APPROX_QUANTILES(valuenum, 100)[OFFSET(75)]
      - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)]
    ),
    2
  ) AS iqr_sbp
FROM sbp_events
WHERE
  bp_category IS NOT NULL
GROUP BY
  bp_category
ORDER BY
  -- Order by the minimum value of each range for logical sorting
  CASE
    WHEN bp_category = '<140'
    THEN 1
    WHEN bp_category = '140-159'
    THEN 2
    WHEN bp_category = '>=160'
    THEN 3
  END;