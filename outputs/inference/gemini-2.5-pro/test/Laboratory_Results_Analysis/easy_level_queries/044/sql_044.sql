WITH stroke_admissions AS (
  -- Step 1: Identify unique hospital admissions for 94-year-old male patients with ischemic stroke
  SELECT DISTINCT
    adm.hadm_id,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'M'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age = 94
    AND LOWER(d_dx.long_title) LIKE '%ischemic stroke%'
),
discharge_glucose AS (
  -- Step 2 & 3: Get all serum glucose values on the day of discharge for these admissions
  SELECT
    le.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN
    stroke_admissions AS sa
    ON le.hadm_id = sa.hadm_id
  WHERE
    -- itemids for Glucose (usually in Serum/Blood)
    le.itemid IN (50931, 50809)
    AND le.valuenum IS NOT NULL
    -- Filter for lab events on the same calendar day as hospital discharge
    AND DATE(le.charttime) = DATE(sa.dischtime)
)
-- Step 4: Calculate the Interquartile Range (IQR) of the collected glucose values
SELECT
  -- APPROX_QUANTILES returns an array: [min, 25th_percentile, median, 75th_percentile, max]
  -- We subtract the 25th (index 1) from the 75th (index 3)
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS glucose_iqr
FROM
  discharge_glucose;