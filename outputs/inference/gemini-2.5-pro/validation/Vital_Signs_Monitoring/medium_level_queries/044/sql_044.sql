WITH
  -- Step 1: Identify the cohort of male ICU patients aged 81-91.
  cohort_stays AS (
    SELECT
      icu.stay_id,
      icu.intime
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 81 AND 91
  ),

  -- Step 2: Gather all SBP measurements for the cohort within the first 48 hours of their ICU stay.
  sbp_measurements AS (
    SELECT
      cs.stay_id,
      ce.valuenum
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      INNER JOIN cohort_stays AS cs
        ON ce.stay_id = cs.stay_id
    WHERE
      -- Filter for SBP itemids (Non-Invasive and Arterial)
      ce.itemid IN (
        220179, -- Non Invasive Blood Pressure systolic
        220050  -- Arterial Blood Pressure systolic
      )
      -- Filter for the first 48 hours of the ICU stay
      AND ce.charttime BETWEEN cs.intime AND TIMESTAMP_ADD(cs.intime, INTERVAL 48 HOUR)
      -- Filter for plausible SBP values to ensure data quality
      AND ce.valuenum IS NOT NULL
      AND ce.valuenum > 0
      AND ce.valuenum < 300
  ),

  -- Step 3: Calculate the average SBP for each ICU stay.
  avg_sbp_per_stay AS (
    SELECT
      stay_id,
      AVG(valuenum) AS avg_sbp
    FROM
      sbp_measurements
    GROUP BY
      stay_id
  )

-- Step 4: Calculate the percentile of an average SBP of 150 mmHg within the cohort's distribution.
SELECT
  -- The percentile is the percentage of stays with an average SBP at or below the value of interest (150).
  (
    COUNTIF(avg_sbp <= 150) / COUNT(avg_sbp)
  ) * 100 AS percentile_of_150_sbp
FROM
  avg_sbp_per_stay;