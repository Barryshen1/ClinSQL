WITH
  -- Step 1: Identify hospital admissions for male patients aged 77-87 with an AMI diagnosis.
  ami_admissions AS (
    SELECT DISTINCT dx.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON pat.subject_id = dx.subject_id
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 77 AND 87
      AND (
        (dx.icd_version = 9 AND dx.icd_code LIKE '410%') -- AMI in ICD-9
        OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I21%') -- AMI in ICD-10
      )
  ),
  -- Step 2: Find the first hs-TnT measurement for each of these admissions.
  first_hsc_tnt AS (
    SELECT
      le.hadm_id,
      le.valuenum,
      -- Rank measurements by time to find the first one
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN ami_admissions AS adm
      ON le.hadm_id = adm.hadm_id
    WHERE
      le.itemid = 52598 -- d_labitems: Troponin T, High Sensitivity
      AND le.valuenum IS NOT NULL
      AND le.valueuom = 'ng/L' -- Ensure we are using the correct units for comparison
  ),
  -- Step 3: Categorize the first measurement based on the provided thresholds.
  categorized_tnt AS (
    SELECT
      hadm_id,
      CASE
        WHEN valuenum < 14
          THEN 'Normal'
        WHEN valuenum BETWEEN 14 AND 52
          THEN 'Borderline'
        WHEN valuenum > 52
          THEN 'Myocardial Injury'
      END AS tnt_category
    FROM first_hsc_tnt
    WHERE
      rn = 1 -- Filter for only the first measurement
  )
-- Step 4: Count the number of patients in each category and calculate the percentage.
SELECT
  tnt_category,
  COUNT(hadm_id) AS number_of_admissions,
  ROUND(100.0 * COUNT(hadm_id) / SUM(COUNT(hadm_id)) OVER (), 2) AS percentage
FROM categorized_tnt
GROUP BY
  tnt_category
ORDER BY
  number_of_admissions DESC;