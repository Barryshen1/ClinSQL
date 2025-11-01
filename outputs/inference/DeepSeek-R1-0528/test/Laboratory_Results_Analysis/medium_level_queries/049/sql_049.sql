WITH troponin_uln AS (
  -- Calculate 99th percentile ULN for all Troponin T measurements
  SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(99)] AS uln
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.itemid IN (50911, 51003)  -- Troponin T tests
    AND le.valuenum IS NOT NULL       -- Exclude non-numeric results
),
eligible_admissions AS (
  -- Get admissions for males aged 49-59
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
),
first_troponin_per_admission AS (
  -- Isolate first Troponin T measurement per admission
  SELECT 
    ea.hadm_id,
    le.valuenum AS first_troponin_value
  FROM eligible_admissions ea
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ea.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.itemid IN (50911, 51003)
    AND le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY ea.hadm_id 
    ORDER BY le.charttime
  ) = 1  -- First measurement per admission
),
cohort AS (
  -- Filter admissions where first Troponin T > ULN
  SELECT 
    hadm_id,
    first_troponin_value
  FROM first_troponin_per_admission, troponin_uln
  WHERE first_troponin_value > uln
)
-- Calculate cohort statistics
SELECT 
  COUNT(hadm_id) AS cohort_size,
  (SELECT uln FROM troponin_uln) AS uln,
  APPROX_QUANTILES(first_troponin_value, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(first_troponin_value, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(first_troponin_value, 100)[OFFSET(75)] AS p75,
  MIN(first_troponin_value) AS min_value,
  MAX(first_troponin_value) AS max_value
FROM cohort;