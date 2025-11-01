WITH acs_admissions AS (
  -- Step 1: Find all hospital admissions with an ACS diagnosis
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for ACS
    (
      icd_version = 9
      AND (
        icd_code LIKE '410%' -- Acute Myocardial Infarction
        OR icd_code = '411.1' -- Unstable Angina
      )
    )
    OR
    -- ICD-10 codes for ACS
    (
      icd_version = 10
      AND (
        icd_code LIKE 'I21%' -- Acute Myocardial Infarction
        OR icd_code LIKE 'I22%' -- Subsequent Myocardial Infarction
        OR icd_code = 'I20.0' -- Unstable Angina
      )
    )
), nadir_troponins AS (
  -- Step 2 & 3: Find the nadir (minimum) troponin for each female ACS admission
  SELECT
    le.hadm_id,
    MIN(le.valuenum) AS nadir_troponin
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN acs_admissions AS acs
    ON le.hadm_id = acs.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON le.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND le.itemid IN (
      51003, -- Troponin T
      51002, -- Troponin I
      52598  -- Troponin I, High Sensitivity
    )
    AND le.valuenum IS NOT NULL
  GROUP BY
    le.hadm_id
)
-- Step 4: Calculate the 25th percentile of all nadir troponin values
SELECT
  APPROX_QUANTILES(nadir_troponin, 100)[OFFSET(25)] AS p25_nadir_troponin
FROM
  nadir_troponins;