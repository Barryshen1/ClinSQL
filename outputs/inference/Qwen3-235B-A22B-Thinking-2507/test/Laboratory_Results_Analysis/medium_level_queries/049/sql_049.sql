WITH uln AS (
  SELECT APPROX_QUANTILES(valuenum, 1000)[OFFSET(990)] AS uln_99
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE itemid = 50341
    AND valuenum IS NOT NULL
),
first_troponin AS (
  SELECT 
    le.subject_id,
    le.valuenum,
    p.anchor_age + (EXTRACT(YEAR FROM le.charttime) - p.anchor_year) AS age_at_event
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON le.subject_id = p.subject_id
  WHERE le.itemid = 50341
    AND le.valuenum IS NOT NULL
    AND p.gender = 'M'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY le.subject_id 
    ORDER BY le.charttime
  ) = 1
),
cohort AS (
  SELECT 
    ft.subject_id,
    ft.valuenum
  FROM first_troponin ft
  CROSS JOIN uln
  WHERE ft.age_at_event BETWEEN 49 AND 59
    AND ft.valuenum > uln.uln_99
)
SELECT 
  COUNT(DISTINCT subject_id) AS cohort_size,
  (SELECT uln_99 FROM uln) AS uln,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75,
  MIN(valuenum) AS min_value,
  MAX(valuenum) AS max_value
FROM cohort;