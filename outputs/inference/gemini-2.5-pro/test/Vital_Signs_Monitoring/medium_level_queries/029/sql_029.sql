WITH
  -- Step 1: Identify the cohort of male ICU patients aged 73-83
  patient_cohort AS (
    SELECT
      icu.stay_id,
      icu.intime
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 73 AND 83
  ),
  -- Step 2: Calculate the mean SpO2 for each patient in the cohort during the first 24 hours
  mean_spo2_per_stay AS (
    SELECT
      cohort.stay_id,
      AVG(ce.valuenum) AS avg_spo2
    FROM
      patient_cohort AS cohort
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON cohort.stay_id = ce.stay_id
    WHERE
      -- SpO2 itemid from d_items (O2 saturation pulseoxymetry)
      ce.itemid = 220277
      -- Filter for measurements within the first 24 hours of the ICU stay
      AND ce.charttime BETWEEN cohort.intime AND DATETIME_ADD(cohort.intime, INTERVAL 24 HOUR)
      -- Data cleaning: only include plausible SpO2 values
      AND ce.valuenum > 0 AND ce.valuenum <= 100
    GROUP BY
      cohort.stay_id
  )
-- Step 3: Calculate what percentage of patients in the cohort had a mean SpO2 <= 92%
SELECT
  -- COUNTIF counts rows where the condition is true. Dividing by the total count gives the proportion.
  -- Multiplying by 100.0 converts it to a percentile.
  (
    COUNTIF(msp.avg_spo2 <= 92) * 100.0 / COUNT(msp.avg_spo2)
  ) AS percentile_of_92_spo2
FROM
  mean_spo2_per_stay AS msp;