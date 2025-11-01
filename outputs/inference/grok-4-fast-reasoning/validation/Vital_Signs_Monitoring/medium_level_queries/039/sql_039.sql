WITH filtered_stays AS (
  SELECT 
    s.subject_id, 
    s.stay_id, 
    s.intime,
    p.gender, 
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
),
measurements AS (
  SELECT 
    ce.subject_id, 
    ce.stay_id, 
    ce.charttime, 
    ce.valuenum AS map_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN filtered_stays fs 
    ON ce.stay_id = fs.stay_id
  WHERE ce.itemid = 220052
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fs.intime
    AND ce.charttime <= TIMESTAMP_ADD(fs.intime, INTERVAL 48 HOUR)
),
stay_averages AS (
  SELECT 
    subject_id, 
    stay_id,
    COUNT(map_value) AS num_measurements,
    AVG(map_value) AS avg_map_first48
  FROM measurements
  GROUP BY subject_id, stay_id
  HAVING num_measurements >= 3
)
SELECT 
  ROUND(AVG(CASE WHEN avg_map_first48 <= 60 THEN 1.0 ELSE 0.0 END) * 100, 2) AS percentile_rank
FROM stay_averages;