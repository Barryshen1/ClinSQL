with chest pain
-- and analyzes their initial high-sensitivity Troponin T (hs-TnT) levels.

-- Step 1: Create a CTE to identify the hospital admissions for the target cohort.
WITH cohort_hadm AS (
    SELECT DISTINCT adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      -- Filter for female patients
      pat.gender = 'F'
      -- Filter for age at admission between 87 and 97
      AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 87 AND 97
      -- Filter for admissions with a diagnosis of chest pain (using common ICD-9 and ICD-10 codes)
      AND (dx.icd_code LIKE '7865%' OR dx.icd_code LIKE 'R07%')
),

-- Step 2: Find the first (index) hs-TnT measurement for each admission in the cohort.
first_tnt AS (
    SELECT
      hadm_id,
      valuenum,
      -- Rank measurements by time to find the first one
      ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY charttime ASC) as rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
      hadm_id IN (SELECT hadm_id FROM cohort_hadm)
      AND itemid = 52598 -- d_labitems: High Sensitivity Troponin T
      AND valuenum IS NOT NULL -- Ensure the value is a number
),

-- Step 3: Categorize the index hs-TnT values based on the provided ranges.
tnt_categorized AS (
    SELECT
      hadm_id,
      valuenum,
      CASE
        WHEN valuenum <= 0.04 THEN 'Normal'
        WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'Borderline'
        WHEN valuenum > 0.1 THEN 'Injury'
        ELSE NULL
      END AS tnt_category
    FROM first_tnt
    WHERE rn = 1 -- Select only the first measurement for each admission
)

-- Step 4: Aggregate the results by category and compute the final statistics.
SELECT
  tnt_category,
  COUNT(hadm_id) AS patient_count,
  SAFE_DIVIDE(COUNT(hadm_id) * 100.0, SUM(COUNT(hadm_id)) OVER()) AS percentage_of_patients,
  AVG(valuenum) AS mean_hs_tnt,
  APPROX_QUANTILES(valuenum, 2)[OFFSET(1)] AS median_hs_tnt,
  (APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)]) AS iqr_hs_tnt
FROM tnt_categorized
WHERE tnt_category IS NOT NULL
GROUP BY tnt_category
ORDER BY
  -- Order the results logically from Normal to Injury
  CASE
    WHEN tnt_category = 'Normal' THEN 1
    WHEN tnt_category = 'Borderline' THEN 2
    WHEN tnt_category = 'Injury' THEN 3
  END;