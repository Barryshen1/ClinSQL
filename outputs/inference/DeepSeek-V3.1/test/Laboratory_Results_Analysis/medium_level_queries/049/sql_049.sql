WITH troponin_t AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%troponin t%' AND fluid = 'Blood'
),
uln AS (
  SELECT 
    APPROX_QUANTILES(le.valuenum, 100) AS percentiles
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN troponin_t USING (itemid)
  WHERE le.valuenum IS NOT NULL
),
first_troponin_per_admission AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.valuenum AS first_troponin,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN troponin_t USING (itemid)
  WHERE le.valuenum IS NOT NULL
),
cohort AS (
  SELECT 
    ft.subject_id,
    ft.hadm_id,
    ft.first_troponin
  FROM first_troponin_per_admission ft
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ft.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON ft.hadm_id = a.hadm_id
  WHERE ft.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND ft.first_troponin > (SELECT percentiles[OFFSET(99)] FROM uln)
)
SELECT 
  COUNT(*) AS cohort_size,
  (SELECT percentiles[OFFSET(99)] FROM uln) AS uln,
  APPROX_QUANTILES(first_troponin, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(first_troponin, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(first_troponin, 100)[OFFSET(75)] AS p75,
  MIN(first_troponin) AS min_value,
  MAX(first_troponin) AS max_value
FROM cohort;