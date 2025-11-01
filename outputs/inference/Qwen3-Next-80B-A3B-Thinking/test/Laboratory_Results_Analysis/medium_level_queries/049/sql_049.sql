WITH all_troponin AS (
  SELECT le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE di.label LIKE '%Troponin T%'
    AND le.valuenum IS NOT NULL
),
uln_99th AS (
  SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY valuenum) AS uln
  FROM all_troponin
),
male_49_59 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 49 AND 59
),
initial_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
  WHERE di.label LIKE '%Troponin T%'
    AND le.valuenum IS NOT NULL
    AND a.subject_id IN (SELECT subject_id FROM male_49_59)
),
cohort AS (
  SELECT it.valuenum
  FROM initial_troponin it
  CROSS JOIN uln_99th u
  WHERE it.rn = 1
    AND it.valuenum > u.uln
)
SELECT 
  COUNT(*) AS cohort_size,
  (SELECT uln FROM uln_99th) AS uln,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS p25,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY valuenum) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) AS p75,
  MIN(valuenum) AS min_value,
  MAX(valuenum) AS max_value
FROM cohort;