WITH 
relevant_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.anchor_age BETWEEN 48 AND 58 AND p.gender = 'F'
),
icu_stays AS (
  SELECT i.subject_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN relevant_patients p ON i.subject_id = p.subject_id
),
heart_rates AS (
  SELECT i.stay_id, AVG(c.valuenum) AS avg_hr
  FROM icu_stays i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON i.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE d.itemid = 220050  
  AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY i.stay_id
),
categorized_hr AS (
  SELECT stay_id,
         CASE
           WHEN avg_hr < 60 THEN '<60'
           WHEN avg_hr BETWEEN 60 AND 99 THEN '60-99'
           WHEN avg_hr BETWEEN 100 AND 119 THEN '100-119'
           ELSE '>=120'
         END AS hr_category
  FROM heart_rates
)
SELECT 
  c.hr_category,
  COUNT(c.stay_id) AS num_stays,
  COUNT(c.stay_id) * 100.0 / (SELECT COUNT(*) FROM categorized_hr) AS percent_distribution
FROM categorized_hr c
GROUP BY c.hr_category
ORDER BY c.hr_category;