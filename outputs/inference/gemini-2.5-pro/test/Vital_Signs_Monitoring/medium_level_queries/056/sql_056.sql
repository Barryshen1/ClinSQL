WITH
  -- Step 1: Identify the cohort of female ICU patients aged 89-99
  cohort_patients AS (
    SELECT DISTINCT
      p.subject_id,
      i.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON p.subject_id = i.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 89 AND 99
  ),

  -- Step 2: Extract and clean temperature measurements for the cohort
  temperatures AS (
    SELECT
      cp.subject_id,
      cp.hadm_id,
      ce.charttime,
      CASE
        WHEN ce.itemid = 223761 -- Temperature Fahrenheit
        THEN (ce.valuenum - 32) * 5.0 / 9.0
        WHEN ce.itemid = 223762 -- Temperature Celsius
        THEN ce.valuenum
      END AS temp_c
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN
      cohort_patients AS cp
      ON ce.subject_id = cp.subject_id AND ce.hadm_id = cp.hadm_id
    WHERE
      ce.itemid IN (223761, 223762)
      AND ce.valuenum IS NOT NULL
      -- Filter for plausible physiological values to remove errors
      AND (
        (ce.itemid = 223761 AND ce.valuenum > 77 AND ce.valuenum < 113) -- Plausible Fahrenheit range (25-45 C)
        OR (ce.itemid = 223762 AND ce.valuenum > 25 AND ce.valuenum < 45) -- Plausible Celsius range
      )
  ),

  -- Step 3: Assign each temperature measurement to a category
  categorized_temps AS (
    SELECT
      *,
      CASE
        WHEN temp_c < 36.0
        THEN 'Hypothermic (<36 C)'
        WHEN temp_c >= 36.0 AND temp_c < 38.0
        THEN 'Normothermic (36-37.9 C)'
        WHEN temp_c >= 38.0
        THEN 'Febrile (>=38 C)'
      END AS temp_category
    FROM
      temperatures
  ),

  -- Step 4: Identify hospital admissions with a Myocardial Infarction diagnosis
  mi_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for Acute Myocardial Infarction
      (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '410')
      -- ICD-10 codes for Acute Myocardial Infarction
      OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I21', 'I22'))
  )

-- Step 5: Final aggregation to calculate metrics for each temperature category
SELECT
  ct.temp_category,
  AVG(ct.temp_c) AS mean_temp_c,
  APPROX_QUANTILES(ct.temp_c, 100)[OFFSET(50)] AS median_temp_c,
  (
    APPROX_QUANTILES(ct.temp_c, 100)[OFFSET(75)] - APPROX_QUANTILES(ct.temp_c, 100)[OFFSET(25)]
  ) AS iqr_temp_c,
  COUNT(DISTINCT ct.subject_id) AS unique_patient_count,
  COUNT(ct.temp_c) AS measurement_count,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN mi.hadm_id IS NOT NULL THEN ct.subject_id END),
    COUNT(DISTINCT ct.subject_id)
  ) AS mi_rate
FROM
  categorized_temps AS ct
LEFT JOIN
  mi_admissions AS mi
  ON ct.hadm_id = mi.hadm_id
WHERE
  ct.temp_category IS NOT NULL
GROUP BY
  ct.temp_category
ORDER BY
  -- Order the categories logically from low to high temperature
  MIN(ct.temp_c);