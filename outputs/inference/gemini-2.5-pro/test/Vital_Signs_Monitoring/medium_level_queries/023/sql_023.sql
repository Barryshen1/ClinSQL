WITH
  -- Step 1: Identify the cohort of female ICU patients aged 62-72.
  cohort AS (
    SELECT
      p.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      (EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age) AS age_at_icustay
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON p.subject_id = i.subject_id
    WHERE
      p.gender = 'F'
  ),
  final_cohort AS (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      intime
    FROM cohort
    WHERE
      age_at_icustay BETWEEN 62 AND 72
  ),
  -- Step 2: Identify hospital admissions with an AKI diagnosis.
  aki_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for Acute renal failure
      (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '584')
      -- ICD-10 codes for Acute kidney injury
      OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'N17')
  ),
  -- Step 3: Get all temperature measurements in the first 24 hours for the cohort.
  first_24h_temps AS (
    SELECT
      fc.stay_id,
      fc.hadm_id,
      CASE
        WHEN ce.itemid = 223761 -- Temperature Fahrenheit
          THEN (ce.valuenum - 32) * 5 / 9
        ELSE ce.valuenum -- Temperature Celsius
      END AS temperature_c
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN final_cohort AS fc
      ON ce.stay_id = fc.stay_id
    WHERE
      ce.itemid IN (223761, 223762)
      AND ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN fc.intime AND DATETIME_ADD(fc.intime, INTERVAL 24 HOUR)
  ),
  -- Step 4: Categorize each valid temperature measurement.
  categorized_temps AS (
    SELECT
      stay_id,
      hadm_id,
      temperature_c,
      CASE
        WHEN temperature_c < 36.0
          THEN 'Hypothermia (<36.0)'
        WHEN temperature_c BETWEEN 36.0 AND 37.9
          THEN 'Normothermia (36.0-37.9)'
        WHEN temperature_c >= 38.0
          THEN 'Hyperthermia (>=38.0)'
        ELSE NULL
      END AS temp_category
    FROM first_24h_temps
    -- Filter for a plausible physiological range after conversion to Celsius
    WHERE
      temperature_c BETWEEN 25 AND 45
  ),
  -- Step 5a: Calculate per-measurement statistics for temperature.
  temp_stats AS (
    SELECT
      temp_category,
      AVG(temperature_c) AS mean_temp,
      APPROX_QUANTILES(temperature_c, 100)[OFFSET(50)] AS median_temp,
      -- IQR = 75th percentile - 25th percentile
      (
        APPROX_QUANTILES(temperature_c, 4)[OFFSET(3)] - APPROX_QUANTILES(temperature_c, 4)[OFFSET(1)]
      ) AS iqr_temp
    FROM categorized_temps
    WHERE
      temp_category IS NOT NULL
    GROUP BY
      temp_category
  ),
  -- Step 5b: Calculate per-patient AKI rate for each category.
  aki_rate_by_category AS (
    SELECT
      unique_stays.temp_category,
      -- Calculate the proportion of stays with an AKI diagnosis
      AVG(CASE WHEN aa.hadm_id IS NOT NULL THEN 1.0 ELSE 0.0 END) AS aki_rate
    FROM (
      -- First, find the unique set of stays that fall into each category
      SELECT DISTINCT
        stay_id,
        hadm_id,
        temp_category
      FROM categorized_temps
      WHERE
        temp_category IS NOT NULL
    ) AS unique_stays
    LEFT JOIN aki_admissions AS aa
      ON unique_stays.hadm_id = aa.hadm_id
    GROUP BY
      unique_stays.temp_category
  )
-- Step 6: Combine the results into a final report.
SELECT
  ts.temp_category AS temperature_category,
  ts.mean_temp,
  ts.median_temp,
  ts.iqr_temp,
  ar.aki_rate
FROM temp_stats AS ts
INNER JOIN aki_rate_by_category AS ar
  ON ts.temp_category = ar.temp_category
ORDER BY
  ts.mean_temp;