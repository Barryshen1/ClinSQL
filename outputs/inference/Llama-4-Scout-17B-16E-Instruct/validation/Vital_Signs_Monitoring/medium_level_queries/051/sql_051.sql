WITH 
-- Filter patients by age and gender
patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE anchor_age BETWEEN 55 AND 65
  AND gender = 'M'
),

-- Extract heart rate data for filtered patients
heart_rates AS (
  SELECT 
    ce.subject_id,
    MAX(CAST(ce.valuenum AS FLOAT64)) AS max_heart_rate
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  JOIN 
    patients_filtered pf ON ce.subject_id = pf.subject_id
  WHERE 
    di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY 
    ce.subject_id
)

-- Calculate interquartile range
SELECT 
  APPROX_QUANTILES(max_heart_rate, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(max_heart_rate, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(max_heart_rate, 100)[OFFSET(75)] - 
  APPROX_QUANTILES(max_heart_rate, 100)[OFFSET(25)] AS iqr
FROM 
  heart_rates;