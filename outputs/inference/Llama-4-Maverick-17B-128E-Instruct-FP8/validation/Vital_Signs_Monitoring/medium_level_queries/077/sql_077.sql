WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 42 AND 52
),
icustay_filter AS (
  SELECT i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patient_filter p ON i.subject_id = p.subject_id
),
heart_rate_avg AS (
  SELECT h.stay_id, AVG(c.valuenum) AS avg_hr
  FROM icustay_filter h
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON h.stay_id = c.stay_id
  WHERE c.itemid = 220050  
  GROUP BY h.stay_id
)
SELECT 
  COUNT(*) AS cohort_size,
  (SELECT COUNT(*) FROM heart_rate_avg WHERE avg_hr <= 90) / COUNT(*) * 100 AS percentile_90_bpm
FROM heart_rate_avg;