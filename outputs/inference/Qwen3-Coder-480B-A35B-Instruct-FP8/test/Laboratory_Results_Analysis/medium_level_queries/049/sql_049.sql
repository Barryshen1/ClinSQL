WITH troponin_t_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) = 'troponin t'
),

first_troponin AS (
  SELECT
    l.subject_id,
    l.valuenum,
    l.charttime,
    l.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_t_itemid t ON l.itemid = t.itemid
  WHERE l.valuenum IS NOT NULL
),

initial_troponin AS (
  SELECT *
  FROM first_troponin
  WHERE rn = 1
),

eligible_patients AS (
  SELECT
    p.subject_id,
    i.valuenum AS first_trop_t,
    i.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN initial_troponin i ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
),

-- Estimate ULN as 99th percentile of first normal values
normal_troponin AS (
  SELECT valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_t_itemid t ON l.itemid = t.itemid
  WHERE l.valuenum IS NOT NULL
    AND (l.flag IS NULL OR LOWER(l.flag) != 'abnormal')
),

uln_estimate AS (
  SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(99)] AS uln
  FROM normal_troponin
),

cohort AS (
  SELECT e.*
  FROM eligible_patients e
  CROSS JOIN uln_estimate u
  WHERE e.first_trop_t > u.uln
)

SELECT
  COUNT(*) AS cohort_size,
  MAX(u.uln) AS uln,
  APPROX_QUANTILES(first_trop_t, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(first_trop_t, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(first_trop_t, 4)[OFFSET(3)] AS p75,
  MIN(first_trop_t) AS min_value,
  MAX(first_trop_t) AS max_value
FROM cohort
CROSS JOIN uln_estimate u;