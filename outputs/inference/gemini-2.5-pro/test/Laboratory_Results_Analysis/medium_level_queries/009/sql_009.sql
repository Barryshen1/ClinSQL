WITH relevant_admissions AS (
  -- Step 1: Identify admissions for female patients aged 59-69
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 59 AND 69
),
first_hs_tnt AS (
  -- Step 2: Find the first High-Sensitivity Troponin T for each admission in the cohort
  SELECT
    ra.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY ra.hadm_id ORDER BY le.charttime) AS rn
  FROM
    relevant_admissions AS ra
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON ra.hadm_id = le.hadm_id
  WHERE
    le.itemid = 52598 -- d_labitems: Troponin T, High Sensitivity
    AND le.valuenum IS NOT NULL
),
qualifying_values AS (
  -- Step 3: Filter for admissions where the first hs-TnT is > 0.014 ng/mL
  SELECT
    valuenum
  FROM
    first_hs_tnt
  WHERE
    rn = 1
    AND valuenum > 0.014
)
-- Step 4: Calculate the min, max, and percentiles for the qualifying hs-TnT values
SELECT
  MIN(valuenum) AS min_hs_tnt,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS percentile_25_hs_tnt,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS percentile_50_hs_tnt,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS percentile_75_hs_tnt,
  MAX(valuenum) AS max_hs_tnt
FROM
  qualifying_values;