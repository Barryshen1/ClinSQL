WITH cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.stay_id,
    i.hadm_id,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON 
    p.subject_id = i.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
),
measurements AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    c.intime,
    ce.charttime,
    ce.valuenum
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    c.subject_id = ce.subject_id
    AND c.hadm_id = ce.hadm_id
    AND c.stay_id = ce.stay_id
  WHERE 
    ce.itemid = 220045
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 400
    AND ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 1 DAY)
)
SELECT 
  bp_category,
  COUNT(*) AS num_measurements,
  AVG(valuenum) AS mean_bp,
  APPROX_QUANTILES(valuenum, 3)[OFFSET(1)] AS median_bp,
  APPROX_QUANTILES(valuenum, 3)[OFFSET(0)] AS q1_bp,
  APPROX_QUANTILES(valuenum, 3)[OFFSET(2)] AS q3_bp,
  APPROX_QUANTILES(valuenum, 3)[OFFSET(2)] - 
  APPROX_QUANTILES(valuenum, 3)[OFFSET(0)] AS iqr_bp
FROM (
  SELECT 
    valuenum,
    CASE 
      WHEN valuenum < 140 THEN '<140'
      WHEN valuenum >= 140 AND valuenum < 160 THEN '140–159'
      ELSE '>=160'
    END AS bp_category
  FROM 
    measurements
)
GROUP BY 
  bp_category
ORDER BY 
  MIN(valuenum);  -- Orders categories naturally (<140, 140–159, >=160);