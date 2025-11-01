WITH
  -- Step 1: Define the cohort of female ICU stays for patients aged 38-48
  cohort_stays AS (
    SELECT
      icu.stay_id,
      icu.intime
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      AND (
        pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year
      ) BETWEEN 38 AND 48
  ),

  -- Step 2: Calculate the average systolic BP for each stay in the first 24 hours
  avg_sbp_per_stay AS (
    SELECT
      ch.stay_id,
      AVG(ch.valuenum) AS avg_sbp
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ch
    INNER JOIN
      cohort_stays AS cs
      ON ch.stay_id = cs.stay_id
    WHERE
      -- ITEMIDs for Systolic Blood Pressure (Non-Invasive and Invasive)
      ch.itemid IN (220179, 220050)
      -- Filter to the first 24 hours of the ICU stay
      AND ch.charttime >= cs.intime
      AND ch.charttime <= DATETIME_ADD(cs.intime, INTERVAL 24 HOUR)
      -- Ensure value is a plausible number
      AND ch.valuenum IS NOT NULL
      AND ch.valuenum > 0
      AND ch.valuenum < 300
    GROUP BY
      ch.stay_id
  )

-- Step 3: Calculate the percentile of a 120 mmHg average SBP within the cohort
SELECT
  -- The percentile is the proportion of stays with an average SBP less than or equal to 120, multiplied by 100.
  SAFE_DIVIDE(
    SUM(
      CASE
        WHEN avg_sbp <= 120
        THEN 1
        ELSE 0
      END
    ) * 100.0,
    COUNT(stay_id)
  ) AS percentile_of_120_sbp
FROM
  avg_sbp_per_stay;