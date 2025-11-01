WITH
  -- Step 1: Identify female patients aged 67-77
  patient_cohort AS (
    SELECT
      p.subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 67 AND 77
  ),
  -- Step 2: Identify hospital admissions with an ACS diagnosis
  acs_admissions AS (
    SELECT DISTINCT
      dx.subject_id, -- MODIFIED: Included subject_id for a direct join later
      dx.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
      ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
    WHERE
      LOWER(ddx.long_title) LIKE '%acute coronary syndrome%'
      OR LOWER(ddx.long_title) LIKE '%unstable angina%'
      OR (
        LOWER(ddx.long_title) LIKE '%myocardial infarction%'
        AND LOWER(ddx.long_title) LIKE '%acute%'
      )
  ),
  -- Step 3: Find the first Troponin T measurement for each admission
  initial_troponin AS (
    SELECT
      le.hadm_id,
      le.valuenum,
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    WHERE
      le.itemid = 51003 -- Troponin T
      AND le.valuenum IS NOT NULL
  ),
  -- Step 4: Combine the cohorts and apply all filters
  final_cohort AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      it.valuenum AS initial_troponin_t
    FROM
      patient_cohort AS p
      -- MODIFIED: Replaced the unsupported subquery with a direct join
    INNER JOIN
      acs_admissions AS a
      ON p.subject_id = a.subject_id
    INNER JOIN
      initial_troponin AS it
      ON a.hadm_id = it.hadm_id
    WHERE
      it.rn = 1 -- Only the initial measurement
      AND it.valuenum > 0.01 -- Above the 99th percentile threshold (0.01 ng/mL)
  )
-- Step 5: Calculate and report final statistics
SELECT
  COUNT(DISTINCT fc.subject_id) AS patient_count,
  COUNT(DISTINCT fc.hadm_id) AS admission_count,
  AVG(fc.initial_troponin_t) AS mean_initial_troponin,
  APPROX_QUANTILES(fc.initial_troponin_t, 100)[OFFSET(50)] AS median_initial_troponin,
  (
    APPROX_QUANTILES(fc.initial_troponin_t, 100)[OFFSET(75)] - APPROX_QUANTILES(fc.initial_troponin_t, 100)[OFFSET(25)]
  ) AS iqr_initial_troponin
FROM
  final_cohort AS fc;