WITH cohort AS (
  SELECT 
    i.stay_id,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 42 AND 52
),
heart_rate_avg AS (
  SELECT 
    c.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 220045  -- Standard heart rate measurement
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id
)
SELECT 
  COUNT(*) AS cohort_size,
  (SUM(CASE WHEN avg_hr <= 90 THEN 1 ELSE 0 END) * 100.0) / COUNT(*) AS percentile
FROM heart_rate_avg;