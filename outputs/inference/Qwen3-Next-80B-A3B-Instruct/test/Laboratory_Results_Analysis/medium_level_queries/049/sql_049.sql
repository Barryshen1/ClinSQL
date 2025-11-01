WITH troponin_uln AS (
  SELECT APPROX_QUANTILES(le.valuenum, 100)[OFFSET(99)] AS uln_99th
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
),
initial_troponin AS (
  SELECT 
    le.subject_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
),
cohort AS (
  SELECT 
    it.valuenum
  FROM initial_troponin it
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON it.subject_id = p.subject_id
  JOIN troponin_uln tu
    ON it.valuenum > tu.uln_99th
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND it.rn = 1
)
SELECT 
  COUNT(*) AS cohort_size,
  (SELECT uln_99th FROM troponin_uln) AS uln,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75,
  MIN(valuenum) AS min_value,
  MAX(valuenum) AS max_value
FROM cohort;