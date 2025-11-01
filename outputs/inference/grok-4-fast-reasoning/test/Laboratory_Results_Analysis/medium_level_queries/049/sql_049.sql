WITH itemid_trop AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label = 'TROPONIN-T'
),
uln_cte AS (
  SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(99)] AS uln
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  CROSS JOIN itemid_trop it
  WHERE le.itemid = it.itemid
    AND valuenum IS NOT NULL
),
first_trop_all AS (
  SELECT 
    le.subject_id, 
    le.valuenum, 
    le.charttime, 
    le.hadm_id,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id ORDER BY le.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  CROSS JOIN itemid_trop it
  WHERE le.itemid = it.itemid
    AND valuenum IS NOT NULL
),
first_trop AS (
  SELECT subject_id, valuenum, charttime, hadm_id
  FROM first_trop_all
  WHERE rn = 1
),
filtered AS (
  SELECT ft.valuenum
  FROM first_trop ft
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ft.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ft.hadm_id = a.hadm_id
  CROSS JOIN uln_cte u
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 49 AND 59
    AND ft.valuenum > u.uln
),
stats AS (
  SELECT 
    COUNT(*) AS cohort_size,
    MIN(valuenum) AS min_value,
    MAX(valuenum) AS max_value,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75
  FROM filtered
)
SELECT 
  cohort_size,
  (SELECT uln FROM uln_cte) AS uln,
  min_value,
  max_value,
  p25,
  p50 AS median,
  p75
FROM stats;