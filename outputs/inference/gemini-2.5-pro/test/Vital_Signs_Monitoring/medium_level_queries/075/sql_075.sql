WITH
  -- Step 1: Define the cohort of male patients aged 56-66
  patient_cohort AS (
    SELECT
      subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'M'
      AND anchor_age BETWEEN 56 AND 66
  ),

  -- Step 2: Calculate the average MAP for each ICU stay
  map_per_stay AS (
    SELECT
      stay_id,
      AVG(valuenum) AS avg_map
    FROM `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE
      itemid IN (
        220052, -- Arterial Blood Pressure mean
        220181, -- Non Invasive Blood Pressure mean
        225312  -- Art BP mean
      )
      AND valuenum > 0 AND valuenum < 300 -- Ensure physiologically plausible values
    GROUP BY
      stay_id
  ),

  -- Step 3: Identify patients with a documented stroke diagnosis (patient-level)
  stroke_patients AS (
    SELECT DISTINCT
      subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (
        icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN (
          '430', '431', '432', '433', '434', '436', '437'
        )
      ) OR (
        icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN (
          'I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67'
        )
      )
  ),

  -- Step 4: Combine cohort, ICU stays, MAP, and stroke information
  -- This CTE results in one row per ICU stay with all necessary flags and values
  stay_level_data AS (
    SELECT
      icu.subject_id,
      map.avg_map,
      CASE
        WHEN sp.subject_id IS NOT NULL THEN 1
        ELSE 0
      END AS had_stroke_diagnosis
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN patient_cohort AS pc
      ON icu.subject_id = pc.subject_id
    INNER JOIN map_per_stay AS map
      ON icu.stay_id = map.stay_id
    LEFT JOIN stroke_patients AS sp
      ON icu.subject_id = sp.subject_id
  ),

  -- Create categories for each stay based on the average MAP
  categorized_stays AS (
    SELECT
      subject_id,
      had_stroke_diagnosis,
      CASE
        WHEN avg_map < 65 THEN '< 65'
        WHEN avg_map >= 65 AND avg_map < 75 THEN '65-74'
        WHEN avg_map >= 75 AND avg_map < 85 THEN '75-84'
        WHEN avg_map >= 85 THEN '>= 85'
      END AS map_category
    FROM stay_level_data
  )

-- Step 5: Final aggregation to get patient counts and stroke rates per category
SELECT
  map_category,
  COUNT(DISTINCT subject_id) AS number_of_patients,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN had_stroke_diagnosis = 1 THEN subject_id ELSE NULL END) * 100.0,
    COUNT(DISTINCT subject_id)
  ) AS stroke_rate_percent
FROM categorized_stays
WHERE
  map_category IS NOT NULL
GROUP BY
  map_category
ORDER BY
  CASE
    WHEN map_category = '< 65' THEN 1
    WHEN map_category = '65-74' THEN 2
    WHEN map_category = '75-84' THEN 3
    WHEN map_category = '>= 85' THEN 4
  END;