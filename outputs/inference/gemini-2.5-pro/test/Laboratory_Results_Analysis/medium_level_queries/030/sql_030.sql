WITH
-- 1. Identify the cohort: female patients aged 64-74 with an AMI diagnosis.
ami_admissions AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'F'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 64 AND 74
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '410%')   -- ICD-9 for AMI
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I21%') -- ICD-10 for AMI
    )
),

-- 2. Find the first (index) high-sensitivity troponin T for each hospital admission.
first_troponin AS (
  SELECT
    hadm_id,
    valuenum
  FROM (
    SELECT
      hadm_id,
      charttime,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
      itemid = 52550 -- Troponin T, High Sensitivity
      AND valuenum IS NOT NULL
      AND valuenum >= 0 -- Ensure value is non-negative
  ) AS ranked_troponin
  WHERE
    rn = 1
),

-- 3. Join the cohort with their index troponin and categorize the value.
-- The INNER JOIN ensures we only consider patients from the cohort who had an hs-TnT test.
categorized_patients AS (
  SELECT
    ami.hadm_id,
    CASE
      WHEN ft.valuenum <= 0.014 THEN 'Normal'
      WHEN ft.valuenum >= 0.015 AND ft.valuenum <= 0.052 THEN 'Borderline'
      WHEN ft.valuenum > 0.052 THEN 'Myocardial Injury'
      ELSE NULL -- Values between 0.014 and 0.015 are not categorized per prompt
    END AS troponin_category
  FROM
    ami_admissions AS ami
  INNER JOIN
    first_troponin AS ft
    ON ami.hadm_id = ft.hadm_id
)

-- 4. Calculate the count and percentage for each category.
SELECT
  troponin_category,
  COUNT(hadm_id) AS number_of_patients,
  ROUND(100 * COUNT(hadm_id) / SUM(COUNT(hadm_id)) OVER (), 2) AS percentage
FROM
  categorized_patients
WHERE
  troponin_category IS NOT NULL -- Exclude patients with uncategorized values from the final result
GROUP BY
  troponin_category
ORDER BY
  -- A custom order to match the prompt's logical flow
  CASE
    WHEN troponin_category = 'Normal' THEN 1
    WHEN troponin_category = 'Borderline' THEN 2
    WHEN troponin_category = 'Myocardial Injury' THEN 3
  END;