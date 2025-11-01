WITH
  -- Step 1: Identify the cohort of female patients aged 87-97 at ICU admission
  patient_cohort AS (
    SELECT
      icu.stay_id,
      icu.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      AND (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year + pat.anchor_age) BETWEEN 87 AND 97
  ),

  -- Step 2: Get all systolic BP measurements for the cohort in the first 24 hours
  first_day_sbp AS (
    SELECT
      pc.stay_id,
      ce.valuenum
    FROM patient_cohort AS pc
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON pc.stay_id = ce.stay_id
    WHERE
      ce.itemid IN (
        220179, -- Non Invasive Blood Pressure systolic
        220050, -- Arterial Blood Pressure systolic
        225309, -- ART BP Systolic
        227243, -- Manual Blood Pressure SBP
        224167, -- Manual Blood Pressure SBP Left
        224166  -- Manual Blood Pressure SBP Right
      )
      AND ce.charttime BETWEEN pc.intime AND DATETIME_ADD(pc.intime, INTERVAL 24 HOUR)
      AND ce.valuenum IS NOT NULL
      AND ce.valuenum > 0 AND ce.valuenum < 400 -- Exclude erroneous values
  ),

  -- Step 3: Calculate the average SBP for each ICU stay
  avg_sbp_per_stay AS (
    SELECT
      stay_id,
      AVG(valuenum) AS avg_sbp
    FROM first_day_sbp
    GROUP BY
      stay_id
  )

-- Step 4: Calculate what percentile a value of 150 mmHg represents
SELECT
  -- This calculates the proportion of stays with an average SBP <= 150
  -- and expresses it as a percentile.
  (
    CAST(COUNTIF(avg_sbp <= 150) AS FLOAT64) / CAST(COUNT(stay_id) AS FLOAT64)
  ) * 100 AS percentile_for_sbp_150
FROM avg_sbp_per_stay;