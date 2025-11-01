WITH troponin_t_uln AS (
  WITH troponin_t_values AS (
    SELECT valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE itemid = 51003 AND valuenum IS NOT NULL
  )
  SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(99)] AS uln_99th_percentile
  FROM troponin_t_values
),
first_troponin_t AS (
  SELECT p.subject_id, 
         le.charttime,
         le.valuenum,
         ROW_NUMBER() OVER (PARTITION BY le.subject_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON le.subject_id = p.subject_id
  WHERE le.itemid = 51003 AND p.gender = 'M' AND p.anchor_age BETWEEN 49 AND 59
),
filtered_cohort AS (
  SELECT valuenum
  FROM first_troponin_t
  WHERE rn = 1 AND valuenum > (SELECT uln_99th_percentile FROM troponin_t_uln)
)
SELECT 
  COUNT(*) AS cohort_size,
  (SELECT uln_99th_percentile FROM troponin_t_uln) AS uln,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75,
  MIN(valuenum) AS min_value,
  MAX(valuenum) AS max_value
FROM filtered_cohort;