WITH
  -- 1. Define the cohort of interest: female ICU patients aged 77-87 at admission.
  cohort_stays AS (
    SELECT
      icu.stay_id,
      icu.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      AND (
        -- Calculate age at the time of ICU admission
        pat.anchor_age + DATETIME_DIFF(icu.intime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR)
      ) BETWEEN 77 AND 87
  ),

  -- 2. Isolate all relevant systolic blood pressure measurements.
  sbp_events AS (
    SELECT
      stay_id,
      charttime,
      valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE
      itemid IN (
        220050, -- Arterial Blood Pressure systolic
        220179  -- Non Invasive Blood Pressure systolic
      )
      AND valuenum IS NOT NULL
      AND valuenum > 0 -- Basic data cleaning
  ),

  -- 3. For each stay in the cohort, calculate the average SBP over the first 48 hours.
  avg_sbp_per_stay AS (
    SELECT
      cohort.stay_id,
      AVG(sbp.valuenum) AS avg_sbp
    FROM cohort_stays AS cohort
    INNER JOIN sbp_events AS sbp
      ON cohort.stay_id = sbp.stay_id
    WHERE
      -- Filter for measurements within the first 48 hours of the ICU stay
      sbp.charttime BETWEEN cohort.intime AND DATETIME_ADD(cohort.intime, INTERVAL 48 HOUR)
    GROUP BY
      cohort.stay_id
  )

-- 4. Calculate the percentile of a 160 mmHg average SBP within the cohort's distribution.
SELECT
  -- The percentile is the percentage of stays with an average SBP less than or equal to the value of interest (160).
  (COUNTIF(avg_sbp <= 160) * 100.0) / COUNT(stay_id) AS percentile_of_160_sbp
FROM avg_sbp_per_stay;