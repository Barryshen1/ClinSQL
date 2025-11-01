WITH cohort_admissions AS (
  -- Step 1: Identify admissions for 45-year-old females with a GI bleeding diagnosis.
  SELECT DISTINCT
    adm.hadm_id,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code
    AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age = 45
    AND (
      LOWER(d_dx.long_title) LIKE '%gastrointestinal bleed%'
      OR LOWER(d_dx.long_title) LIKE '%gastrointestinal hemorrhage%'
    )
),
discharge_day_hgb AS (
  -- Step 2: Find all valid hemoglobin measurements on the day of discharge for the cohort.
  SELECT
    le.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN
    cohort_admissions AS ca
    ON le.hadm_id = ca.hadm_id
  WHERE
    -- itemid for Hemoglobin
    le.itemid = 51222
    -- Ensure the value is a number and the unit is g/dL
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'g/dL'
    -- Filter for lab events on the calendar day of discharge
    AND DATE(le.charttime) = DATE(ca.dischtime)
)
-- Step 3: Calculate the 75th percentile of the collected hemoglobin values.
SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS hemoglobin_75th_percentile_g_dl
FROM
  discharge_day_hgb;