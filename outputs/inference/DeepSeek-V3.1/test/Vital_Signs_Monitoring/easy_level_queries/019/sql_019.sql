WITH bp_events AS (
  SELECT 
    ce.subject_id, 
    ce.stay_id, 
    ce.charttime,
    MAX(CASE WHEN ce.itemid = 220179 THEN ce.valuenum END) AS systolic_bp,
    MAX(CASE WHEN ce.itemid = 220180 THEN ce.valuenum END) AS diastolic_bp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (220179, 220180)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.subject_id, ce.stay_id, ce.charttime
  HAVING systolic_bp IS NOT NULL AND diastolic_bp IS NOT NULL
),
map_per_event AS (
  SELECT 
    subject_id,
    stay_id,
    charttime,
    (systolic_bp + 2 * diastolic_bp) / 3 AS map_value
  FROM bp_events
),
avg_map_per_stay AS (
  SELECT 
    stay_id,
    AVG(map_value) AS mean_map
  FROM map_per_event
  GROUP BY stay_id
)
SELECT 
  AVG(mean_map) AS overall_avg_map
FROM avg_map_per_stay amps
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie 
  ON amps.stay_id = ie.stay_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON ie.subject_id = p.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 73 AND 83
  AND ie.first_careunit IN ('Step Down', 'Intermediate Care');