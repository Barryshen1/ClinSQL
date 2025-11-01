WITH cohort AS (
  SELECT 
    p.subject_id,
    i.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 37 AND 47
),
first_spo2_times AS (
  SELECT 
    ce.stay_id,
    MIN(ce.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort c
    ON ce.stay_id = c.stay_id
  WHERE 
    ce.itemid = 220277  -- SpO2 itemid
  GROUP BY ce.stay_id
),
first_spo2_values AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS first_spo2  -- Average if multiple values at first time
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN first_spo2_times f
    ON ce.stay_id = f.stay_id 
    AND ce.charttime = f.first_charttime
  WHERE 
    ce.itemid = 220277
    AND ce.valuenum IS NOT NULL  -- Ensure numeric value exists
  GROUP BY ce.stay_id
)
SELECT 
  APPROX_QUANTILES(first_spo2, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(first_spo2, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(first_spo2, 100)[OFFSET(75)] - APPROX_QUANTILES(first_spo2, 100)[OFFSET(25)] AS iqr
FROM first_spo2_values;