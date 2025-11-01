WITH relevant_admissions AS (
  SELECT a.hadm_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 54 AND 64
),
initial_troponin_t AS (
  SELECT ra.hadm_id, l.valuenum,
         ROW_NUMBER() OVER (PARTITION BY ra.hadm_id ORDER BY l.charttime) AS rn
  FROM relevant_admissions ra
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON ra.hadm_id = l.hadm_id
  WHERE l.itemid = 50821 AND l.valuenum IS NOT NULL
)
SELECT 
  COUNT(*) AS n,
  AVG(valuenum) AS mean,
  STDDEV(valuenum) AS std_dev,
  MIN(valuenum) AS min_val,
  MAX(valuenum) AS max_val,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS percentile_75
FROM initial_troponin_t
WHERE rn = 1 AND valuenum > 0.01;