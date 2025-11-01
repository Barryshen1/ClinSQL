WITH eligible_stays AS (
  SELECT i.stay_id
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
),
heart_rate_values AS (
  SELECT es.stay_id,
         ce.valuenum AS heart_rate
  FROM eligible_stays es
  INNER JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON es.stay_id = ce.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 30
    AND ce.valuenum < 200
),
avg_heart_rate_per_stay AS (
  SELECT stay_id,
         AVG(heart_rate) AS avg_heart_rate
  FROM heart_rate_values
  GROUP BY stay_id
)
SELECT 
  COUNT(*) AS cohort_size,
  SUM(CASE WHEN avg_heart_rate <= 90 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile
FROM avg_heart_rate_per_stay;