WITH patient_details AS (
  SELECT p.subject_id, p.anchor_age, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 54 AND 64
),
rr_measurements AS (
  SELECT pd.stay_id, ce.valuenum, ce.charttime, pd.intime
  FROM patient_details pd
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON pd.stay_id = ce.stay_id
  WHERE ce.itemid = 220210  
  AND ce.charttime BETWEEN pd.intime AND TIMESTAMP_ADD(pd.intime, INTERVAL 48 HOUR)
),
average_rr AS (
  SELECT stay_id, AVG(valuenum) AS avg_rr
  FROM rr_measurements
  GROUP BY stay_id
),
categorized_rr AS (
  SELECT stay_id,
         CASE
           WHEN avg_rr < 12 THEN '<12'
           WHEN avg_rr BETWEEN 12 AND 20 THEN '12-20'
           WHEN avg_rr BETWEEN 21 AND 29 THEN '21-29'
           ELSE '>=30'
         END AS rr_category,
         avg_rr
  FROM average_rr
)
SELECT rr_category,
       COUNT(*) AS n,
       AVG(avg_rr) AS mean,
       APPROX_QUANTILES(avg_rr, 100)[OFFSET(50)] AS median,
       APPROX_QUANTILES(avg_rr, 100)[OFFSET(75)] - APPROX_QUANTILES(avg_rr, 100)[OFFSET(25)] AS iqr
FROM categorized_rr
GROUP BY rr_category
ORDER BY rr_category;