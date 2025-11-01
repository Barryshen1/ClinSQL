WITH cohort AS (
  SELECT 
    i.stay_id,
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    i.intime,
    i.outtime,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p  -- Fixed dataset
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    -- Filter age 48-58 at ICU admission
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 48 AND 58
),

map_events AS (
  SELECT 
    c.stay_id,
    ce.valuenum AS map_value
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce  -- Consistent ICU dataset
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid IN (220052, 220181, 225312)  -- MAP itemids
    AND ce.valuenum IS NOT NULL  -- Ensure numeric values
),

max_map_per_stay AS (
  SELECT 
    stay_id,
    MAX(map_value) AS max_map
  FROM map_events
  GROUP BY stay_id
)

SELECT 
  AVG(max_map) AS average_max_map
FROM max_map_per_stay;