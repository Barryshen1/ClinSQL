WITH troponin_uln AS (
  -- Step 1: Calculate the 99th percentile of the Upper Limit of Normal (ULN)
  -- for all Troponin T tests in the dataset.
  SELECT
    APPROX_QUANTILES(le.ref_range_upper, 100) [OFFSET(99)] AS uln_99th_percentile
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  WHERE
    le.itemid = 51003 -- Troponin T
    AND le.ref_range_upper IS NOT NULL
), initial_troponin_for_cohort AS (
  -- Step 2: Identify the initial Troponin T measurement for each male patient aged 49-59.
  SELECT
    p.subject_id,
    le.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON p.subject_id = le.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND le.itemid = 51003 -- Troponin T
    AND le.valuenum IS NOT NULL
  -- Use QUALIFY to get the first measurement for each patient based on charttime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY le.charttime) = 1
), final_cohort AS (
  -- Step 3: Filter the cohort to include only patients whose initial Troponin T
  -- exceeds the calculated 99th percentile ULN.
  SELECT
    i.valuenum
  FROM
    initial_troponin_for_cohort AS i,
    troponin_uln
  WHERE
    i.valuenum > troponin_uln.uln_99th_percentile
)
-- Step 4: Calculate and report the final statistics for the cohort.
SELECT
  (
    SELECT uln_99th_percentile FROM troponin_uln
  ) AS troponin_t_99th_percentile_uln,
  COUNT(valuenum) AS cohort_size,
  MIN(valuenum) AS min_value,
  APPROX_QUANTILES(valuenum, 100) [OFFSET(25)] AS p25_value,
  APPROX_QUANTILES(valuenum, 100) [OFFSET(50)] AS median_p50_value,
  APPROX_QUANTILES(valuenum, 100) [OFFSET(75)] AS p75_value,
  MAX(valuenum) AS max_value
FROM
  final_cohort;