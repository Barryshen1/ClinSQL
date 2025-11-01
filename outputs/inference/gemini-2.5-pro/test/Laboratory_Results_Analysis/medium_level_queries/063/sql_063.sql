WITH acs_hadm AS (
  -- Identify hospital admissions with a diagnosis of Acute Coronary Syndrome (ACS)
  -- This includes Acute Myocardial Infarction and Unstable Angina.
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for ACS
    (icd_version = 9 AND (
      SUBSTR(icd_code, 1, 3) = '410' -- Acute Myocardial Infarction
      OR icd_code = '4111'          -- Unstable Angina (Intermediate coronary syndrome)
    )) OR
    -- ICD-10 codes for ACS
    (icd_version = 10 AND (
      SUBSTR(icd_code, 1, 3) = 'I21' -- Acute Myocardial Infarction
      OR icd_code = 'I200'           -- Unstable Angina
    ))
),
patient_cohort AS (
  -- Select female patients aged 84-94 at the time of admission
  SELECT
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    -- Calculate age at admission and filter
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 84 AND 94
),
initial_troponin AS (
  -- Find the first Troponin I measurement for each hospital admission
  SELECT
    hadm_id,
    valuenum,
    ref_range_upper
  FROM (
    SELECT
      hadm_id,
      charttime,
      valuenum,
      ref_range_upper,
      ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY charttime ASC) as rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
      itemid = 50912 -- itemid for Troponin I
      AND valuenum IS NOT NULL -- Ensure the value is numeric
  )
  WHERE rn = 1 -- Select only the first measurement
)
-- Main query to join cohorts, apply the final filter, and calculate statistics
SELECT
    COUNT(it.valuenum) AS count_of_patients,
    AVG(it.valuenum) AS mean_troponin_i,
    APPROX_QUANTILES(it.valuenum, 100)[OFFSET(50)] AS median_troponin_i,
    (APPROX_QUANTILES(it.valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(it.valuenum, 100)[OFFSET(25)]) AS iqr_troponin_i
FROM patient_cohort AS pc
-- Join with ACS admissions to filter for the correct diagnosis
INNER JOIN acs_hadm AS ah
  ON pc.hadm_id = ah.hadm_id
-- Join with initial troponin values
INNER JOIN initial_troponin AS it
  ON pc.hadm_id = it.hadm_id
-- Filter for patients whose Troponin I exceeded the upper limit of normal
WHERE
  it.valuenum > it.ref_range_upper
  AND it.ref_range_upper IS NOT NULL;