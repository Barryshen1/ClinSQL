WITH
  -- Step 1: Define the cohort of patients: females aged 79-89 with a heart failure diagnosis at any point.
  hf_patient_cohort AS (
    SELECT DISTINCT
      pat.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON pat.subject_id = dx.subject_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 79 AND 89
      -- Heart Failure ICD-9 codes start with '428', ICD-10 codes with 'I50'
      AND (
        dx.icd_code LIKE '428%' OR dx.icd_code LIKE 'I50%'
      )
  ),
  -- Step 2: For each patient in the cohort, find their first hospital admission and calculate its LOS.
  first_admissions_los AS (
    SELECT
      TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    -- Ensure we only consider patients from our defined cohort
    INNER JOIN hf_patient_cohort AS cohort
      ON adm.subject_id = cohort.subject_id
    -- Use QUALIFY to efficiently select only the first admission for each patient
    QUALIFY
      ROW_NUMBER()
        OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime ASC) = 1
  ),
  -- Step 3: Calculate the quantiles (min, Q1, median, Q3, max) for the LOS distribution.
  los_quantiles AS (
    SELECT
      APPROX_QUANTILES(los_days, 4) AS quantiles
    FROM first_admissions_los
    -- Filter out invalid LOS values resulting from data errors
    WHERE
      los_days >= 0
  )
-- Step 4: Calculate the IQR (Q3 - Q1) from the quantiles.
SELECT
  -- The array is 0-indexed: [min, Q1, median, Q3, max]
  -- Q3 is at offset 3, Q1 is at offset 1.
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS los_iqr
FROM los_quantiles;