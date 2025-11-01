WITH female_dka_admissions AS (
  -- Step 1: Identify hospital admissions for female patients with DKA
  SELECT
    dx.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON dx.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND dx.icd_code IN (
      -- ICD-9 codes for DKA
      '25010', -- Diabetes with ketoacidosis, type II or unspecified, not stated as uncontrolled
      '25011', -- Diabetes with ketoacidosis, type I, not stated as uncontrolled
      '25012', -- Diabetes with ketoacidosis, type II or unspecified, uncontrolled
      '25013', -- Diabetes with ketoacidosis, type I, uncontrolled
      -- ICD-10 codes for DKA
      'E1010', -- Type 1 diabetes mellitus with ketoacidosis without coma
      'E1110', -- Type 2 diabetes mellitus with ketoacidosis without coma
      'E1310' -- Other specified diabetes mellitus with ketoacidosis without coma
    )
  GROUP BY
    dx.hadm_id -- Use GROUP BY to get unique admissions
),
peak_glucose_per_admission AS (
  -- Step 2: Find the peak serum glucose for each of these admissions
  SELECT
    fdka.hadm_id,
    MAX(le.valuenum) AS peak_glucose
  FROM female_dka_admissions AS fdka
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON fdka.hadm_id = le.hadm_id
  WHERE
    le.itemid = 50931 -- 50931 is the itemid for 'Glucose' in the main lab (serum)
    AND le.valuenum IS NOT NULL -- Ensure the value is a number
  GROUP BY
    fdka.hadm_id
)
-- Step 3: Calculate the median of all the peak glucose values
SELECT
  APPROX_QUANTILES(peak_glucose, 100)[OFFSET(50)] AS median_peak_serum_glucose
FROM peak_glucose_per_admission;