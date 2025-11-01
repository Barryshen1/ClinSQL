WITH
  -- 1. Identify hospital admissions for Acute Coronary Syndrome (ACS)
  acs_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      icd_code IN (
        SELECT DISTINCT
          icd_code
        FROM
          `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
        WHERE
          (
            LOWER(long_title) LIKE '%acute myocardial infarction%'
            OR LOWER(long_title) LIKE '%unstable angina%'
          )
      )
  ),
  -- 2. Identify the first Troponin I measurement for each admission
  first_troponin AS (
    SELECT
      hadm_id,
      valuenum,
      -- Rank troponin results for each admission by charttime to find the first one
      ROW_NUMBER() OVER (
        PARTITION BY
          hadm_id
        ORDER BY
          charttime ASC
      ) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
      itemid = 51003 -- Troponin I
      AND valuenum IS NOT NULL -- Ensure the value is numeric
  ),
  -- 3. Define the patient cohort based on demographics
  patient_cohort AS (
    SELECT
      p.subject_id,
      a.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
      -- Calculate age at admission and filter
      AND (
        DATETIME_DIFF(
          a.admittime,
          DATETIME(p.anchor_year, 1, 1, 0, 0, 0),
          YEAR
        ) + p.anchor_age
      ) BETWEEN 68 AND 78
  )
-- 4. Join cohorts, filter, and calculate final statistics
SELECT
  COUNT(DISTINCT pc.subject_id) AS patient_count,
  COUNT(DISTINCT pc.hadm_id) AS admission_count,
  AVG(ft.valuenum) AS mean_first_troponin_i,
  STDDEV(ft.valuenum) AS stddev_first_troponin_i,
  MIN(ft.valuenum) AS min_first_troponin_i,
  MAX(ft.valuenum) AS max_first_troponin_i
FROM
  patient_cohort AS pc
  INNER JOIN acs_admissions AS acs ON pc.hadm_id = acs.hadm_id
  INNER JOIN first_troponin AS ft ON pc.hadm_id = ft.hadm_id
WHERE
  ft.rn = 1 -- Only the first troponin measurement
  AND ft.valuenum > 0.04; -- With a value exceeding 0.04 ng/mL;