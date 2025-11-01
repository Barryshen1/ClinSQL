WITH eligible_stays AS (
  SELECT i.stay_id, i.subject_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 56 AND 66
),
map_data AS (
  SELECT es.stay_id, c.valuenum
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON c.subject_id = es.subject_id
    AND c.stay_id = es.stay_id
  WHERE c.itemid = 220052
    AND c.valuenum IS NOT NULL
    AND c.charttime >= es.intime
    AND c.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
),
stay_means AS (
  SELECT 
    stay_id, 
    AVG(valuenum) AS mean_map
  FROM map_data
  GROUP BY stay_id
)
SELECT 
  CASE
    WHEN mean_map < 65 THEN '<65'
    WHEN mean_map < 75 THEN '65-74'
    WHEN mean_map < 85 THEN '75-84'
    ELSE '>=85'
  END AS category,
  COUNT(*) AS count,
  AVG(mean_map) AS mean,
  APPROX_QUANTILES(mean_map, 3)[OFFSET(1)] AS median,
  (APPROX_QUANTILES(mean_map, 5)[OFFSET(3)] - APPROX_QUANTILES(mean_map, 5)[OFFSET(1)]) AS iqr
FROM stay_means
GROUP BY category;