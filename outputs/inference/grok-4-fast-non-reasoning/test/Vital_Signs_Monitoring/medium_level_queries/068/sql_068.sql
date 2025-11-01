WITH eligible_patients AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
),
map_measurements AS (
  SELECT 
    ep.subject_id,
    ep.stay_id,
    c.charttime,
    c.valuenum AS map_value
  FROM 
    eligible_patients ep
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON 
    c.subject_id = ep.subject_id 
    AND c.stay_id = ep.stay_id
  WHERE 
    c.itemid = 220052  -- MAP from d_items
    AND c.valuenum IS NOT NULL
    AND c.charttime BETWEEN ep.intime AND ep.outtime
)
SELECT 
  CASE 
    WHEN map_value < 65 THEN '<65'
    WHEN map_value >= 65 AND map_value <= 74 THEN '65-74'
    WHEN map_value >= 75 AND map_value <= 84 THEN '75-84'
    WHEN map_value >= 85 THEN '>=85'
  END AS map_category,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS measurement_count,
  ROUND((COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ()), 2) AS stroke_rate_percent
FROM 
  map_measurements
GROUP BY 
  map_category
ORDER BY 
  MIN(map_value);