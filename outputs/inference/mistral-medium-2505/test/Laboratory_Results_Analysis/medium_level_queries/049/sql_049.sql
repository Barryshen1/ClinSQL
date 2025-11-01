WITH
-- First, identify the itemid for Troponin T
troponin_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin T%'
  LIMIT 1
),

-- Get all Troponin T measurements for male patients aged 49-59
troponin_measurements AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS troponin_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON le.subject_id = p.subject_id
  JOIN troponin_item ti ON le.itemid = ti.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND le.valuenum IS NOT NULL
),

-- Get the first Troponin T measurement per admission
first_troponin AS (
  SELECT
    subject_id,
    hadm_id,
    troponin_value,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime) AS rn
  FROM troponin_measurements
),

-- Calculate the 99th percentile ULN for the population
uln_calculation AS (
  SELECT
    PERCENTILE_CONT(le.valuenum, 0.99) AS uln_99th
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON le.subject_id = p.subject_id
  JOIN troponin_item ti ON le.itemid = ti.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND le.valuenum IS NOT NULL
),

-- Final cohort with elevated initial Troponin T
elevated_troponin_cohort AS (
  SELECT
    ft.subject_id,
    ft.hadm_id,
    ft.troponin_value,
    uc.uln_99th
  FROM first_troponin ft
  CROSS JOIN uln_calculation uc
  WHERE
    ft.rn = 1
    AND ft.troponin_value > uc.uln_99th
)

-- Calculate the requested statistics
SELECT
  COUNT(*) AS cohort_size,
  MAX(uln_99th) AS uln_99th_percentile,
  PERCENTILE_CONT(troponin_value, 0.25) AS p25,
  PERCENTILE_CONT(troponin_value, 0.5) AS median_p50,
  PERCENTILE_CONT(troponin_value, 0.75) AS p75,
  MIN(troponin_value) AS min_value,
  MAX(troponin_value) AS max_value
FROM elevated_troponin_cohort;