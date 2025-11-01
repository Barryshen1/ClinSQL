WITH
-- Step 1: Identify hospital admissions with a diagnosis of Heart Failure
hf_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for Heart Failure
    STARTS_WITH(icd_code, '428')
    -- ICD-10 codes for Heart Failure
    OR STARTS_WITH(icd_code, 'I50')
),

-- Step 2: Identify hospital admissions with a diagnosis of COPD
copd_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for COPD and related conditions
    STARTS_WITH(icd_code, '491') -- Chronic bronchitis
    OR STARTS_WITH(icd_code, '492') -- Emphysema
    OR icd_code = '496'               -- Chronic airway obstruction, not elsewhere classified
    -- ICD-10 codes for COPD
    OR STARTS_WITH(icd_code, 'J44') -- Other chronic obstructive pulmonary disease
),

-- Step 3: Find admissions that have BOTH Heart Failure and COPD by intersecting the two sets
admissions_with_both AS (
  SELECT hadm_id FROM hf_admissions
  INTERSECT DISTINCT
  SELECT hadm_id FROM copd_admissions
),

-- Step 4: Identify the final cohort of admissions based on demographics and calculate LOS
cohort_los AS (
  SELECT
    -- Calculate hospital length of stay in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  -- Ensure the admission has both required diagnoses
  INNER JOIN admissions_with_both AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    -- Filter for female patients
    pat.gender = 'F'
    -- Calculate age at admission and filter for the 77-87 range
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 77 AND 87
)

-- Step 5: Calculate the standard deviation of the LOS for the final cohort
SELECT
  STDDEV(los_days) AS sd_hospital_los_days
FROM cohort_los
-- A sanity check to ensure LOS is a positive value
WHERE los_days > 0;