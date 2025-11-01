WITH troponin_t_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

-- Step 2: Define cohort: men aged 49–59
cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 49 AND 59
),

-- Step 3: Get initial Troponin T per admission
initial_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    MIN(l.charttime) AS initial_charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_t_items tti ON l.itemid = tti.itemid
  JOIN cohort c ON l.subject_id = c.subject_id
  WHERE l.valuenum IS NOT NULL
    AND l.valuenum > 0
  GROUP BY l.subject_id, l.hadm_id
),

-- Step 4: Get initial Troponin T value for each admission
initial_troponin_values AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum AS initial_troponin_t
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN initial_troponin it
    ON l.subject_id = it.subject_id
    AND l.hadm_id = it.hadm_id
    AND l.charttime = it.initial_charttime
  JOIN troponin_t_items tti ON l.itemid = tti.itemid
)

-- Step 5: Calculate ULN (99th percentile) for initial Troponin T in cohort
, uln AS (
  SELECT
    APPROX_QUANTILES(initial_troponin_t, 100)[OFFSET(99)] AS uln_99
  FROM initial_troponin_values
)

-- Step 6: Filter admissions where initial Troponin T > ULN
, cohort_exceeding_uln AS (
  SELECT
    itv.subject_id,
    itv.hadm_id,
    itv.initial_troponin_t
  FROM initial_troponin_values itv
  CROSS JOIN uln
  WHERE itv.initial_troponin_t > uln.uln_99
)

-- Step 7: Summary statistics
SELECT
  COUNT(*) AS cohort_size,
  (SELECT uln_99 FROM uln) AS uln_99th_percentile,
  APPROX_QUANTILES(initial_troponin_t, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(initial_troponin_t, 2)[OFFSET(1)] AS median,
  APPROX_QUANTILES(initial_troponin_t, 4)[OFFSET(3)] AS p75,
  MIN(initial_troponin_t) AS min_value,
  MAX(initial_troponin_t) AS max_value
FROM cohort_exceeding_uln;