WITH

-- Step 1: Identify the ICU stays for the target population (females aged 38-48)
target_stays AS (
  SELECT
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    -- Calculate age at the time of ICU admission for accuracy
    AND (
      p.anchor_age + DATETIME_DIFF(i.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)
    ) BETWEEN 38 AND 48
),

-- Step 2: Calculate the mean SpO2 for every ICU stay
spo2_per_stay AS (
  SELECT
    stay_id,
    AVG(valuenum) AS mean_spo2
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    -- itemid 220277 is 'O2 saturation pulseoxymetry'
    itemid = 220277
    -- Filter for plausible SpO2 values
    AND valuenum > 0 AND valuenum <= 100
  GROUP BY
    stay_id
)

-- Step 3: Combine the data and calculate the final percentile
SELECT
  COUNTIF(sps.mean_spo2 <= 92) AS num_stays_le_92,
  COUNT(sps.stay_id) AS total_stays_in_cohort,
  SAFE_DIVIDE(
    COUNTIF(sps.mean_spo2 <= 92) * 100.0,
    COUNT(sps.stay_id)
  ) AS percentile_of_92
FROM
  spo2_per_stay AS sps
-- Filter the SpO2 calculations to only include stays from our target population
INNER JOIN
  target_stays AS ts
  ON sps.stay_id = ts.stay_id;