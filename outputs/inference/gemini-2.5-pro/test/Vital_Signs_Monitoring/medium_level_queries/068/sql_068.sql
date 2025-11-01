WITH
  -- 1. Identify the cohort of female ICU patients aged 41-51
  icu_cohort AS (
    SELECT
      p.subject_id,
      i.hadm_id,
      i.stay_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON p.subject_id = i.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 41 AND 51
  ),
  -- 2. Identify hospital admissions with a stroke diagnosis
  stroke_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for cerebrovascular disease / stroke
      SUBSTR(icd_code, 1, 3) IN ('430', '431', '432', '433', '434', '436')
      -- ICD-10 codes for cerebrovascular disease / stroke
      OR SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62', 'I63', 'I64')
  ),
  -- 3. Get all MAP measurements for the cohort and categorize them
  categorized_map AS (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      CASE
        WHEN ce.valuenum < 65
        THEN '<65'
        WHEN ce.valuenum >= 65 AND ce.valuenum < 75
        THEN '65-74'
        WHEN ce.valuenum >= 75 AND ce.valuenum < 85
        THEN '75-84'
        WHEN ce.valuenum >= 85
        THEN '>=85'
        ELSE NULL
      END AS map_category
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN
      icu_cohort AS icu
      ON ce.stay_id = icu.stay_id
    WHERE
      ce.itemid IN (
        220052, -- Arterial Blood Pressure mean
        220181, -- Non Invasive Blood Pressure mean
        225312 -- ART BP mean
      )
      AND ce.valuenum IS NOT NULL
      AND ce.valuenum > 0 AND ce.valuenum < 300 -- Sanity check for plausible values
  )
-- 4. Aggregate results by MAP category to count patients and calculate stroke rates
SELECT
  map.map_category,
  COUNT(DISTINCT map.subject_id) AS patient_count,
  COUNT(
    DISTINCT CASE WHEN sa.hadm_id IS NOT NULL THEN map.subject_id END
  ) AS stroke_patient_count,
  SAFE_DIVIDE(
    COUNT(
      DISTINCT CASE WHEN sa.hadm_id IS NOT NULL THEN map.subject_id END
    ),
    COUNT(DISTINCT map.subject_id)
  ) AS stroke_rate
FROM
  categorized_map AS map
LEFT JOIN
  stroke_admissions AS sa
  ON map.hadm_id = sa.hadm_id
WHERE
  map.map_category IS NOT NULL
GROUP BY
  map.map_category
ORDER BY
  CASE map.map_category
    WHEN '<65'
    THEN 1
    WHEN '65-74'
    THEN 2
    WHEN '75-84'
    THEN 3
    WHEN '>=85'
    THEN 4
  END;