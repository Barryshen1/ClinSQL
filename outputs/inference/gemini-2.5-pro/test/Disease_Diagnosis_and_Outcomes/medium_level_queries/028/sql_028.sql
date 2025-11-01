WITH
-- Step 1: Identify all hospital admissions for male patients aged 43-53
-- and calculate the length of stay (LOS) for each valid admission.
patient_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    -- Ensure LOS is valid and non-negative
    AND a.dischtime >= a.admittime
),

-- Step 2: Identify all hospital admissions with a diagnosis of Heart Failure (HF).
-- ICD-9 codes for HF start with '428'. ICD-10 codes start with 'I50'.
hf_admissions AS (
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for Heart Failure
    icd_code LIKE '428%'
    -- ICD-10 codes for Heart Failure
    OR icd_code LIKE 'I50%'
),

-- Step 3: Calculate the comorbidity burden for each admission,
-- defined here as the total number of diagnoses recorded.
comorbidity_burden AS (
  SELECT
    hadm_id,
    COUNT(icd_code) AS diagnosis_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),

-- Step 4: Combine the cohort, diagnosis, and comorbidity data.
-- Then, use window functions to create LOS quartiles and comorbidity tertiles.
stratified_cohort AS (
  SELECT
    pc.hadm_id,
    pc.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY pc.los_days) AS los_quartile,
    NTILE(3) OVER (ORDER BY cb.diagnosis_count) AS comorbidity_tertile
  FROM
    patient_cohort AS pc
  -- Keep only admissions with a Heart Failure diagnosis
  INNER JOIN
    hf_admissions AS hf
    ON pc.hadm_id = hf.hadm_id
  -- Add the comorbidity burden information
  INNER JOIN
    comorbidity_burden AS cb
    ON pc.hadm_id = cb.hadm_id
  -- NTILE function requires non-null ordering values
  WHERE pc.los_days IS NOT NULL
)

-- Step 5: Final aggregation and presentation.
-- Group by the strata and calculate the in-hospital mortality percentage for each group.
SELECT
  CASE
    WHEN s.comorbidity_tertile = 1 THEN 'Low'
    WHEN s.comorbidity_tertile = 2 THEN 'Medium'
    WHEN s.comorbidity_tertile = 3 THEN 'High'
  END AS comorbidity_burden,
  CONCAT('Q', CAST(s.los_quartile AS STRING)) AS los_quartile,
  COUNT(s.hadm_id) AS number_of_admissions,
  -- AVG(flag) * 100 gives the percentage of rows where the flag is 1.
  ROUND(AVG(s.hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct
FROM
  stratified_cohort AS s
GROUP BY
  s.comorbidity_tertile,
  s.los_quartile
ORDER BY
  -- Order by the numeric tertile/quartile for correct sorting ('Low' -> 'Medium' -> 'High', 'Q1' -> 'Q4')
  s.comorbidity_tertile,
  s.los_quartile;