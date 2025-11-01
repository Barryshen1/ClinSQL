WITH patient_selection AS (
  SELECT p.subject_id, p.anchor_age, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 45 AND 55
),
heart_rate_measurements AS (
  SELECT ps.subject_id, ce.valuenum
  FROM patient_selection ps
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ps.stay_id = ce.stay_id
  WHERE ce.itemid = 220050  
  AND ce.charttime >= ps.intime + INTERVAL 2 DAY
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS Q1,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS Q3,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS IQR
FROM heart_rate_measurements;