WITH acs_admissions AS (
  -- Step 1: Identify all hospital admissions for male patients with an ACS diagnosis.
  SELECT DISTINCT
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON dx.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (
      -- ICD-9 codes for Acute Myocardial Infarction and Unstable Angina
      (dx.icd_version = 9 AND (dx.icd_code LIKE '410%' OR dx.icd_code = '4111'))
      -- ICD-10 codes for Acute Myocardial Infarction and Unstable Angina
      OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'I21%' OR dx.icd_code = 'I200'))
    )
), peak_troponins AS (
  -- Step 2 & 3: Find the peak troponin level for each of the ACS admissions.
  SELECT
    acs.hadm_id,
    MAX(le.valuenum) AS peak_troponin
  FROM
    acs_admissions AS acs
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON acs.hadm_id = le.hadm_id
  WHERE
    -- itemid for Troponin T (51003) and Troponin I (51002)
    le.itemid IN (51003, 51002)
    AND le.valuenum IS NOT NULL
  GROUP BY
    acs.hadm_id
)
-- Step 4: Calculate the 75th percentile of the peak troponin values.
SELECT
  APPROX_QUANTILES(peak_troponin, 100)[OFFSET(75)] AS troponin_75th_percentile
FROM
  peak_troponins;