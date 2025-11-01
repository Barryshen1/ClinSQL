WITH troponin_ids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
initial_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS troponin_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN troponin_ids AS t
    ON le.itemid = t.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON le.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND le.valuenum IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
),
uln_cte AS (
  -- approximate 99th percentile (ULN) over all initial values
  SELECT
    APPROX_QUANTILES(troponin_value, 100)[OFFSET(99)] AS uln_99
  FROM initial_troponin
),
filtered AS (
  -- keep only those admissions where the initial value exceeds the ULN
  SELECT
    i.*
  FROM initial_troponin AS i
  CROSS JOIN uln_cte AS u
  WHERE i.troponin_value > u.uln_99
),
summary AS (
  SELECT
    COUNT(*) AS cohort_size,
    ANY_VALUE(u.uln_99) AS ULN,
    APPROX_QUANTILES(f.troponin_value, 4) AS quarts,
    MIN(f.troponin_value) AS min_value,
    MAX(f.troponin_value) AS max_value
  FROM filtered AS f
  CROSS JOIN uln_cte AS u
)
SELECT
  cohort_size,
  ULN,
  quarts[OFFSET(1)] AS p25,
  quarts[OFFSET(2)] AS median,
  quarts[OFFSET(3)] AS p75,
  min_value,
  max_value
FROM summary;