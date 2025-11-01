WITH
  cohort AS (
    -- Step 1: Identify ICU stays for female patients aged 75-85
    SELECT
      p.subject_id,
      icu.stay_id,
      icu.intime
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON p.subject_id = icu.subject_id
    WHERE
      p.gender = 'F'
      -- Calculate age at ICU admission
      AND (
        p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year
      ) BETWEEN 75 AND 85
  ),

  sbp_measurements AS (
    -- Step 2: Extract systolic blood pressure measurements within the first 48 hours
    SELECT
      c.stay_id,
      ce.valuenum
    FROM
      cohort AS c
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON c.stay_id = ce.stay_id
    WHERE
      -- ITEMIDs for Systolic Blood Pressure (both invasive and non-invasive)
      ce.itemid IN (220179, 220050)
      -- Filter to the first 48 hours of the ICU stay
      AND ce.charttime >= c.intime AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
      -- Filter for plausible, non-null numeric values
      AND ce.valuenum IS NOT NULL
      AND ce.valuenum > 0 AND ce.valuenum < 300
  ),

  mean_sbp_per_stay AS (
    -- Step 3: Calculate the mean SBP for each stay
    SELECT
      stay_id,
      AVG(valuenum) AS mean_sbp
    FROM
      sbp_measurements
    GROUP BY
      stay_id
  )

-- Step 4: Calculate the percentile of a 140 mmHg mean SBP in the cohort
SELECT
  -- Percentile is the % of stays with a mean SBP at or below the target value
  SAFE_DIVIDE(
    COUNTIF(mean_sbp <= 140),
    COUNT(stay_id)
  ) * 100 AS percentile_of_140_sbp
FROM
  mean_sbp_per_stay;