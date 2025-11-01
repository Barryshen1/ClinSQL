WITH troponin_99th AS (
  SELECT
    APPROX_QUANTILES(valuenum, 1000)[OFFSET(990)] AS uln_99
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
),
patients_of_interest AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
),
first_troponin_t AS (
  SELECT
    le.subject_id,
    MIN(le.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  JOIN patients_of_interest p
    ON le.subject_id = p.subject_id
  WHERE LOWER(dli.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
  GROUP BY le.subject_id
),
initial_troponin_values AS (
  SELECT
    le.subject_id,
    le.valuenum AS first_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN first_troponin_t ftt
    ON le.subject_id = ftt.subject_id AND le.charttime = ftt.first_charttime
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
),
cohort_with_uln AS (
  SELECT
    itv.first_value,
    t99.uln_99
  FROM initial_troponin_values itv
  CROSS JOIN troponin_99th t99
  WHERE itv.first_value > t99.uln_99
)
SELECT
  COUNT(*) AS cohort_size,
  ROUND(ANY_VALUE(uln_99), 4) AS ULN_99th_percentile,
  ROUND(APPROX_QUANTILES(first_value, 1000)[OFFSET(250)], 4) AS p25,
  ROUND(APPROX_QUANTILES(first_value, 1000)[OFFSET(500)], 4) AS p50,
  ROUND(APPROX_QUANTILES(first_value, 1000)[OFFSET(750)], 4) AS p75,
  ROUND(MIN(first_value), 4) AS min_value,
  ROUND(MAX(first_value), 4) AS max_value
FROM cohort_with_uln;