WITH patient_stays AS (
  SELECT 
    i.stay_id,
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  WHERE 
    p.gender = 'M' AND p.anchor_age BETWEEN 83 AND 93
),
map_measurements AS (
  SELECT 
    c.stay_id,
    c.charttime,
    c.valuenum AS map_value,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN 
    patient_stays ps ON c.stay_id = ps.stay_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i ON c.stay_id = i.stay_id
  WHERE 
    c.itemid = 220052  -- Verify this itemid
    AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
),
average_map AS (
  SELECT 
    stay_id,
    AVG(map_value) AS avg_map
  FROM 
    map_measurements
  GROUP BY 
    stay_id
  HAVING 
    COUNT(*) >= 3
)
SELECT 
  COUNTIF(avg_map <= 60) * 100.0 / COUNT(*) AS percentile
FROM 
  average_map;