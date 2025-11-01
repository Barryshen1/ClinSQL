WITH
  -- Step 1: Identify the cohort of ICU stays for male patients aged 71-81
  cohort_stays AS (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON icu.subject_id = p.subject_id
    WHERE
      p.gender = 'M'
      AND (
        p.anchor_age + DATETIME_DIFF(icu.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)
      ) BETWEEN 71 AND 81
  ),
  -- Step 2: Extract and normalize temperature readings from the first 48 hours of each stay
  temps_in_first_48h AS (
    SELECT
      cs.stay_id,
      -- Convert Fahrenheit to Celsius, handle both units
      CASE
        WHEN ce.itemid = 223761
        THEN (ce.valuenum - 32) * 5 / 9 -- Temperature Fahrenheit
        WHEN ce.itemid = 223762
        THEN ce.valuenum -- Temperature Celsius
        ELSE NULL
      END AS temperature_celsius
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN
      cohort_stays AS cs
      ON ce.stay_id = cs.stay_id
    WHERE
      ce.itemid IN (
        223761, -- Temperature Fahrenheit (MetaVision)
        223762 -- Temperature Celsius (MetaVision)
      )
      -- Filter for measurements within the first 48 hours of the ICU stay
      AND ce.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
      AND ce.valuenum IS NOT NULL AND ce.valuenum > 0 -- Basic data cleaning
  ),
  -- Step 3: Calculate the average temperature for each stay
  stay_avg_temps AS (
    SELECT
      t.stay_id,
      cs.hadm_id,
      AVG(t.temperature_celsius) AS avg_temp_celsius
    FROM
      temps_in_first_48h AS t
    -- Re-join to cohort_stays to get hadm_id for each stay_id
    INNER JOIN
      cohort_stays AS cs
      ON t.stay_id = cs.stay_id
    GROUP BY
      t.stay_id,
      cs.hadm_id
    HAVING
      AVG(t.temperature_celsius) IS NOT NULL -- Ensure stays have valid temperature readings
  ),
  -- Step 4: Identify hospital admissions with a Myocardial Infarction (MI) diagnosis
  mi_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for MI (410.x)
      (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '410')
      -- ICD-10 codes for MI (I21.x, I22.x)
      OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I21', 'I22'))
  ),
  -- Step 5: Categorize stays by temperature and flag for MI
  categorized_stays AS (
    SELECT
      st.stay_id,
      st.avg_temp_celsius,
      -- Categorize based on average temperature
      CASE
        WHEN st.avg_temp_celsius < 36.0
        THEN '<36.0'
        WHEN st.avg_temp_celsius >= 36.0 AND st.avg_temp_celsius <= 37.9
        THEN '36.0-37.9'
        WHEN st.avg_temp_celsius >= 38.0
        THEN '>=38.0'
        ELSE NULL
      END AS temp_category,
      -- Flag if the admission had an MI diagnosis (1 for MI, 0 for no MI)
      CASE
        WHEN mi.hadm_id IS NOT NULL
        THEN 1
        ELSE 0
      END AS mi_flag
    FROM
      stay_avg_temps AS st
    LEFT JOIN
      mi_admissions AS mi
      ON st.hadm_id = mi.hadm_id
  )
-- Final step: Aggregate the results by temperature category
SELECT
  cs.temp_category,
  COUNT(cs.stay_id) AS number_of_stays,
  -- Calculate stats for the average temperature within each category
  AVG(cs.avg_temp_celsius) AS mean_avg_temp,
  APPROX_QUANTILES(cs.avg_temp_celsius, 100)[OFFSET(50)] AS median_avg_temp,
  (
    APPROX_QUANTILES(cs.avg_temp_celsius, 100)[OFFSET(75)] - APPROX_QUANTILES(cs.avg_temp_celsius, 100)[OFFSET(25)]
  ) AS iqr_avg_temp,
  -- Calculate the MI rate (average of the 0/1 mi_flag)
  AVG(cs.mi_flag) AS mi_rate
FROM
  categorized_stays AS cs
WHERE
  cs.temp_category IS NOT NULL
GROUP BY
  cs.temp_category
ORDER BY
  -- Order by the category for readability, e.g., '<36.0', '36.0-37.9', '>=38.0'
  MIN(cs.avg_temp_celsius);