WITH

-- Step 1: Identify all hospital admissions with a stroke-related diagnosis.
stroke_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for cerebrovascular diseases
    SUBSTR(icd_code, 1, 3) IN ('430', '431', '432', '433', '434', '436', '437') OR
    -- ICD-10 codes for cerebrovascular diseases
    SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67')
),

-- Step 2: Identify the first hospital admission for each patient.
first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime
  FROM (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      ROW_NUMBER() OVER(PARTITION BY subject_id ORDER BY admittime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  )
  WHERE rn = 1
),

-- Step 3: Get the Length of Stay (LOS) for the first ICU stay within each hospital admission.
first_icu_stays AS (
  SELECT
    hadm_id,
    los
  FROM (
    SELECT
      hadm_id,
      los,
      ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY intime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),

-- Step 4: Construct the final cohort by joining the above and applying demographic filters.
cohort_los AS (
  SELECT
    ficu.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  -- Join to the first admission of the patient
  INNER JOIN first_admissions AS fa
    ON p.subject_id = fa.subject_id
  -- Ensure that first admission was for a stroke
  INNER JOIN stroke_hadm AS sh
    ON fa.hadm_id = sh.hadm_id
  -- Get the LOS from the first ICU stay of that admission
  INNER JOIN first_icu_stays AS ficu
    ON fa.hadm_id = ficu.hadm_id
  WHERE
    -- Filter for male patients
    p.gender = 'M'
    -- Filter for patients aged 46-56 at the time of their first admission
    AND (p.anchor_age + EXTRACT(YEAR FROM fa.admittime) - p.anchor_year) BETWEEN 46 AND 56
)

-- Step 5: Calculate the Interquartile Range (IQR) of ICU LOS for the final cohort.
SELECT
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_icu_los_days
FROM (
  SELECT APPROX_QUANTILES(los, 4) AS quantiles
  FROM cohort_los
);