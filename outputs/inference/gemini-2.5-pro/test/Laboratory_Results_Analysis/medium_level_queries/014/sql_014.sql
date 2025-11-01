WITH
  -- Step 1: Identify all hospital admissions with a diagnosis of Acute Coronary Syndrome (ACS)
  acs_hadm_ids AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for Acute Myocardial Infarction and Unstable Angina
      (
        icd_version = 9
        AND (
          icd_code LIKE '410%' -- Acute Myocardial Infarction
          OR icd_code = '4111' -- Intermediate coronary syndrome/Unstable Angina
        )
      )
      OR
      -- ICD-10 codes for Acute Myocardial Infarction and Unstable Angina
      (
        icd_version = 10
        AND (
          icd_code LIKE 'I21%' -- Acute Myocardial Infarction
          OR icd_code LIKE 'I22%' -- Subsequent STEMI and NSTEMI
          OR icd_code = 'I200' -- Unstable Angina
        )
      )
  ),
  -- Step 2: Filter the ACS admissions to the specified cohort: males aged 79-89
  cohort_admissions AS (
    SELECT
      adm.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON adm.subject_id = pat.subject_id
      INNER JOIN acs_hadm_ids ON adm.hadm_id = acs_hadm_ids.hadm_id
    WHERE
      pat.gender = 'M'
      -- Calculate age at admission and filter
      AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 79 AND 89
  ),
  -- Step 3: Find the first Troponin T measurement for each admission in the cohort
  initial_troponin AS (
    SELECT
      le.hadm_id,
      le.valuenum,
      -- Rank the measurements by time to find the first one
      ROW_NUMBER() OVER (
        PARTITION BY
          le.hadm_id
        ORDER BY
          le.charttime
      ) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      INNER JOIN cohort_admissions AS ca ON le.hadm_id = ca.hadm_id
    WHERE
      le.itemid = 51003 -- 51003 is the itemid for Troponin T
      AND le.valuenum IS NOT NULL
  ),
  -- Step 4: Categorize the initial troponin values based on clinical thresholds
  categorized_troponin AS (
    SELECT
      hadm_id,
      CASE
        WHEN valuenum < 0.01
        THEN 'Normal'
        WHEN valuenum BETWEEN 0.01 AND 0.03
        THEN 'Borderline'
        WHEN valuenum > 0.03
        THEN 'Elevated'
        ELSE 'Uncategorized'
      END AS troponin_category
    FROM
      initial_troponin
    WHERE
      rn = 1 -- Only consider the first measurement for each admission
  )
-- Final Step: Aggregate the counts and calculate percentages for each category
SELECT
  troponin_category,
  COUNT(hadm_id) AS number_of_patients,
  ROUND(
    100.0 * COUNT(hadm_id) / SUM(COUNT(hadm_id)) OVER (),
    2
  ) AS percentage_of_patients
FROM
  categorized_troponin
GROUP BY
  troponin_category
ORDER BY
  -- Custom order to display categories logically
  CASE
    troponin_category
    WHEN 'Normal'
    THEN 1
    WHEN 'Borderline'
    THEN 2
    WHEN 'Elevated'
    THEN 3
    ELSE 4
  END;