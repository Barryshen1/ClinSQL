WITH eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, ie.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 55 AND 65
),
max_heart_rates AS (
  SELECT ep.subject_id, MAX(ce.valuenum) AS max_hr
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ep.stay_id = ce.stay_id
  WHERE ce.itemid = 220050  
  GROUP BY ep.subject_id
)
SELECT 
  APPROX_QUANTILES(max_hr, 100)[OFFSET(25)] AS Q1,
  APPROX_QUANTILES(max_hr, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(max_hr, 100)[OFFSET(75)] AS Q3,
  APPROX_QUANTILES(max_hr, 100)[OFFSET(75)] - APPROX_QUANTILES(max_hr, 100)[OFFSET(25)] AS IQR
FROM max_heart_rates;