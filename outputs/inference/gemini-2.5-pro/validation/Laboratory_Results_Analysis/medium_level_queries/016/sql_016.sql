WITH
  -- Step 1: Identify the cohort of male patients aged 79-89 admitted with an ACS-related diagnosis.
  patient_cohort AS (
    SELECT DISTINCT
      diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON diag.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON adm.subject_id = p.subject_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 79 AND 89
      AND (
        -- ICD-9 codes for ACS
        (
          diag.icd_version = 9
          AND (
            diag.icd_code LIKE '410%'  -- Acute Myocardial Infarction
            OR diag.icd_code = '4111'  -- Intermediate coronary syndrome (Unstable Angina)
          )
        )
        -- ICD-10 codes for ACS
        OR (
          diag.icd_version = 10
          AND (
            diag.icd_code LIKE 'I21%'  -- Acute Myocardial Infarction
            OR diag.icd_code LIKE 'I22%'  -- Subsequent STEMI and NSTEMI
            OR diag.icd_code = 'I200'  -- Unstable angina
            OR diag.icd_code LIKE 'I24%'  -- Other acute ischemic heart diseases
          )
        )
      )
  ),

  -- Step 2: Find the first Troponin T measurement for each admission in the cohort.
  first_troponin AS (
    SELECT
      pc.hadm_id,
      le.valuenum,
      -- Rank troponin results by time to find the first one
      ROW_NUMBER() OVER (PARTITION BY pc.hadm_id ORDER BY le.charttime) AS rn
    FROM patient_cohort AS pc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON pc.hadm_id = le.hadm_id
    WHERE
      le.itemid = 51003  -- Troponin T
      AND le.valuenum IS NOT NULL
  ),

  -- Step 3: Categorize the initial troponin values.
  categorized_troponin AS (
    SELECT
      hadm_id,
      valuenum,
      CASE
        WHEN valuenum < 0.01
        THEN 'Normal (< 0.01 ng/mL)'
        WHEN valuenum BETWEEN 0.01 AND 0.03
        THEN 'Borderline (0.01-0.03 ng/mL)'
        WHEN valuenum > 0.03
        THEN 'Elevated (> 0.03 ng/mL)'
      END AS troponin_category
    FROM first_troponin
    WHERE
      rn = 1
  )

-- Step 4: Aggregate results by category and calculate final statistics.
SELECT
  troponin_category,
  COUNT(hadm_id) AS count_of_patients,
  SAFE_DIVIDE(COUNT(hadm_id) * 100.0, SUM(COUNT(hadm_id)) OVER ()) AS percentage_of_patients,
  AVG(valuenum) AS mean_troponin_t,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS median_troponin_t,
  (
    APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)]
  ) AS iqr_troponin_t
FROM categorized_troponin
GROUP BY
  troponin_category
ORDER BY
  -- Custom sort order for logical presentation
  CASE
    WHEN troponin_category = 'Normal (< 0.01 ng/mL)'
    THEN 1
    WHEN troponin_category = 'Borderline (0.01-0.03 ng/mL)'
    THEN 2
    WHEN troponin_category = 'Elevated (> 0.03 ng/mL)'
    THEN 3
  END;