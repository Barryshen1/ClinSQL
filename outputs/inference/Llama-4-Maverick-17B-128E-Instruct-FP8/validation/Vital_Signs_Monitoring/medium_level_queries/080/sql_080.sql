WITH patient_age AS (
  SELECT p.subject_id, p.gender, 
         EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age AS age_at_icu_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
),
filtered_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime
  FROM patient_age pa
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON pa.subject_id = i.subject_id
  WHERE pa.age_at_icu_admit BETWEEN 56 AND 66
),
map_values AS (
  SELECT f.stay_id, c.valuenum AS map_value
  FROM filtered_stays f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON f.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE d.label = 'Arterial Blood Pressure Mean' 
    AND c.charttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 48 HOUR)
),
mean_map_per_stay AS (
  SELECT stay_id, AVG(map_value) AS mean_map
  FROM map_values
  GROUP BY stay_id
),
categorized_map AS (
  SELECT stay_id,
         CASE
           WHEN mean_map < 65 THEN '<65'
           WHEN mean_map BETWEEN 65 AND 74 THEN '65-74'
           WHEN mean_map BETWEEN 75 AND 84 THEN '75-84'
           ELSE '>=85'
         END AS map_category,
         mean_map
  FROM mean_map_per_stay
)
SELECT 
  map_category,
  COUNT(*) AS count,
  AVG(mean_map) AS mean,
  APPROX_QUANTILES(mean_map, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(mean_map, 100)[OFFSET(75)] - APPROX_QUANTILES(mean_map, 100)[OFFSET(25)] AS iqr
FROM categorized_map
GROUP BY map_category
ORDER BY map_category;