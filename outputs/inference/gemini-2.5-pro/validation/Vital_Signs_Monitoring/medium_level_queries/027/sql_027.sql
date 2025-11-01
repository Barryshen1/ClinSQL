WITH avg_hr_per_stay AS (
  -- Step 1: Calculate the average heart rate for each ICU stay.
  -- We select only valid, physiological heart rate measurements.
  SELECT
    stay_id,
    AVG(valuenum) AS avg_hr
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid IN (
      220045, -- Heart Rate (from d_items)
      211 -- Heart Rate (from d_items, older itemid)
    )
    AND valuenum > 0 AND valuenum < 300 -- Sanity check for physiological heart rates
  GROUP BY
    stay_id
),

filtered_population_hr AS (
  -- Step 2: Filter for the target population: female ICU patients aged 80-90.
  -- We join the average heart rates with patient demographics.
  SELECT
    hr.avg_hr
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN
    avg_hr_per_stay AS hr
    ON icu.stay_id = hr.stay_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 80 AND 90
)

-- Step 3: Calculate the percentile for a value of 110 bpm.
-- This is done by finding the proportion of stays with an average heart rate
-- less than or equal to 110.
SELECT
  COUNTIF(avg_hr <= 110) AS stays_at_or_below_110,
  COUNT(avg_hr) AS total_stays_in_cohort,
  SAFE_DIVIDE(COUNTIF(avg_hr <= 110), COUNT(avg_hr)) * 100 AS percentile_of_110_bpm
FROM
  filtered_population_hr;