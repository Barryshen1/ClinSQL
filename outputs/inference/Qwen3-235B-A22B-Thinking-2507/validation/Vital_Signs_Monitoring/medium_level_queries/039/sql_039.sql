WITH cohort AS (
  SELECT 
    stays.stay_id,
    stays.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` stays
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON stays.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM stays.intime) - (p.anchor_year - p.anchor_age)) BETWEEN 83 AND 93
),
map_measurements AS (
  SELECT 
    c.stay_id,
    ce.valuenum AS map_value
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 220052  -- Standard MIMIC-IV itemid for MAP
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),
stay_averages AS (
  SELECT 
    stay_id,
    AVG(map_value) AS avg_map
  FROM map_measurements
  GROUP BY stay_id
  HAVING COUNT(*) >= 3  -- Minimum 3 measurements requirement
)
SELECT 
  IF(COUNT(*) > 0,
     (COUNTIF(avg_map <= 60) * 100.0) / COUNT(*),
     NULL) AS percentile
FROM stay_averages;