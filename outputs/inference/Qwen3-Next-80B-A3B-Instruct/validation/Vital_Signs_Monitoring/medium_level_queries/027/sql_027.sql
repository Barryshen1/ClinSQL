WITH female_icu_patients AS (
  SELECT i.stay_id
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),
heart_rate_measurements AS (
  SELECT c.stay_id, c.valuenum
  FROM physionet-data.mimiciv_3_1_icu.chartevents c
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE d.label = 'Heart Rate'
    AND c.valuenum IS NOT NULL
    AND c.valuenum >= 30
    AND c.valuenum <= 200
),
per_stay_avg_hr AS (
  SELECT stay_id, AVG(valuenum) AS avg_heart_rate
  FROM heart_rate_measurements
  GROUP BY stay_id
)
SELECT 
  (SUM(CASE WHEN avg_heart_rate <= 110 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percentile
FROM per_stay_avg_hr;