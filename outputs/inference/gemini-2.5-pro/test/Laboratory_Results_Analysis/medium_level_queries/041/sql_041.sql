WITH
  -- Step 1: Identify hospital admissions for Acute Coronary Syndrome (ACS)
  acs_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for Acute Myocardial Infarction or Unstable Angina
      (
        icd_version = 9
        AND (
          SUBSTR(icd_code, 1, 3) = '410' OR icd_code = '4111'
        )
      ) -- ICD-10 codes for Acute Myocardial Infarction or Unstable Angina
      OR (
        icd_version = 10
        AND (
          STARTS_WITH(icd_code, 'I21') OR icd_code = 'I200'
        )
      )
  ),
  -- Step 2: Define the patient cohort: males aged 43-53 with an ACS admission
  patient_cohort AS (
    SELECT
      a.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN
      acs_admissions AS acs
      ON a.hadm_id = acs.hadm_id
    WHERE
      p.gender = 'M'
      AND (
        (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age
      ) BETWEEN 43 AND 53
  ),
  -- Step 3: Find the first hs-Troponin T measurement for each hospital admission
  initial_troponin AS (
    SELECT
      hadm_id,
      valuenum,
      ref_range_upper
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
      itemid = 52598 -- d_labitems.label = 'Troponin T, High Sensitivity'
      AND valuenum IS NOT NULL
      AND valueuom = 'ng/mL' -- Ensure correct unit
    QUALIFY
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) = 1
  )
-- Final Step: Join the cohort with their initial troponin, filter for values > ULN, and calculate statistics
SELECT
  APPROX_QUANTILES(it.valuenum, 100) [OFFSET(50)] AS median_ng_mL,
  (
    APPROX_QUANTILES(it.valuenum, 100) [OFFSET(75)] - APPROX_QUANTILES(it.valuenum, 100) [OFFSET(25)]
  ) AS iqr_ng_mL,
  APPROX_QUANTILES(it.valuenum, 100) [OFFSET(25)] AS p25_ng_mL,
  APPROX_QUANTILES(it.valuenum, 100) [OFFSET(75)] AS p75_ng_mL
FROM
  patient_cohort AS pc
INNER JOIN
  initial_troponin AS it
  ON pc.hadm_id = it.hadm_id
WHERE
  it.valuenum > it.ref_range_upper; -- Filter for values > 99th percentile ULN;