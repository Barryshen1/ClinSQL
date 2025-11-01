WITH
  -- Step 1: Identify hospital admissions for female patients aged 88-98 with an ACS diagnosis
  acs_admissions AS (
    SELECT DISTINCT
      adm.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'F'
      -- Calculate age at admission and filter for the 88-98 range
      AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 88 AND 98
      -- Filter for ICD codes related to Acute Coronary Syndrome (ACS)
      AND (
        -- ICD-9 codes for AMI (410.x) and Unstable Angina (411.1)
        (dx.icd_version = 9 AND (dx.icd_code LIKE '410%' OR dx.icd_code = '4111'))
        -- ICD-10 codes for AMI (I21.x), subsequent AMI (I22.x), and Unstable Angina (I20.0)
        OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%' OR dx.icd_code = 'I200'))
      )
  ),
  -- Step 2: Find the first Troponin T measurement for each of these admissions
  first_troponin AS (
    SELECT
      le.hadm_id,
      le.valuenum,
      -- Assign a rank to each measurement based on its charttime to find the earliest one
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      INNER JOIN acs_admissions AS adm
        ON le.hadm_id = adm.hadm_id
    WHERE
      le.itemid = 51003 -- 51003 is the itemid for 'Troponin T'
      AND le.valuenum IS NOT NULL -- Ensure the value is a number
      AND le.valueuom = 'ng/mL' -- Ensure the unit is correct
  )
-- Step 3: Calculate median and IQR on the first troponin values that are > 0.01 ng/mL
SELECT
  -- Calculate the 50th percentile (median)
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_troponin_t_ng_ml,
  -- Calculate the Interquartile Range (75th percentile - 25th percentile)
  (APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)]) AS iqr_troponin_t_ng_ml
FROM
  first_troponin
WHERE
  rn = 1 -- Only consider the first measurement for each admission
  AND valuenum > 0.01; -- Apply the value filter from the question;