WITH avg_spo2 AS (
  SELECT ce.stay_id, AVG(ce.valuenum) AS avg_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid = 220277  
  GROUP BY ce.stay_id
),
filtered_stays AS (
  SELECT i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 80 AND 90
)
SELECT 
  COUNT(CASE WHEN a.avg_spo2 <= 88 THEN 1 END) / COUNT(*) * 100 AS percentile
FROM avg_spo2 a
JOIN filtered_stays f ON a.stay_id = f.stay_id;