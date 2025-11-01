WITH 
patients AS (
  SELECT p.subject_id, p.anchor_age, ic.stay_id, ic.hadm_id, ic.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON p.subject_id = ic.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 51 AND 61
),

spo2_measurements AS (
  SELECT ce.stay_id, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN patients p ON ce.stay_id = p.stay_id
  WHERE ce.itemid = 220277  
  AND ce.charttime <= TIMESTAMP_ADD(p.intime, INTERVAL 48 HOUR)
),

avg_spo2 AS (
  SELECT stay_id, AVG(valuenum) AS avg_spo2_value
  FROM spo2_measurements
  GROUP BY stay_id
),

spo2_categories AS (
  SELECT stay_id,
         CASE
           WHEN AVG(valuenum) < 90 THEN '<90'
           WHEN AVG(valuenum) BETWEEN 90 AND 92 THEN '90-92'
           WHEN AVG(valuenum) BETWEEN 93 AND 95 THEN '93-95'
           ELSE '>95'
         END AS spo2_category
  FROM spo2_measurements
  GROUP BY stay_id
),

aki_events AS (
  SELECT p.hadm_id, 
         MAX(CASE WHEN le.valuenum > 2 THEN 1 ELSE 0 END) AS had_aki  
  FROM patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON p.hadm_id = le.hadm_id
  WHERE le.itemid = 50806  
  GROUP BY p.hadm_id
)

SELECT 
  sc.spo2_category,
  COUNT(DISTINCT p.stay_id) AS patient_count,
  AVG(ae.had_aki) AS aki_rate
FROM patients p
JOIN spo2_categories sc ON p.stay_id = sc.stay_id
LEFT JOIN aki_events ae ON p.hadm_id = ae.hadm_id
GROUP BY sc.spo2_category
ORDER BY sc.spo2_category;