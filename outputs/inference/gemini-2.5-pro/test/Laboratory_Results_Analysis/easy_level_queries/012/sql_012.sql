WITH
  target_patients AS (
    -- Step 1: Identify 87-year-old female patients
    SELECT
      p.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE
      p.gender = 'F'
      AND p.anchor_age = 87
  ),
  hemorrhagic_stroke_admissions AS (
    -- Step 2: Identify hospital admissions with a hemorrhagic stroke diagnosis
    SELECT DISTINCT
      diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
      ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
    WHERE
      -- Using specific ICD titles is more accurate than a broad search
      d_diag.long_title LIKE '%Intracerebral hemorrhage%'
      OR d_diag.long_title LIKE '%Subarachnoid hemorrhage%'
  )
-- Step 3: Join the cohort with lab results on discharge day and calculate the percentile
SELECT
  APPROX_QUANTILES(le.valuenum, 100)[OFFSET(75)] AS platelet_count_75th_percentile
FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
-- Join with admissions to get the discharge time for the temporal filter
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON le.hadm_id = adm.hadm_id
-- Ensure the admission was for a hemorrhagic stroke
INNER JOIN hemorrhagic_stroke_admissions AS hsa
  ON le.hadm_id = hsa.hadm_id
-- Ensure the patient matches the demographic criteria
INNER JOIN target_patients AS tp
  ON le.subject_id = tp.subject_id
WHERE
  -- Filter for platelet count (itemid 51265)
  le.itemid = 51265
  -- Ensure the value is a number for calculation
  AND le.valuenum IS NOT NULL
  -- Filter for lab tests performed on the calendar day of discharge
  AND DATE(le.charttime) = DATE(adm.dischtime);