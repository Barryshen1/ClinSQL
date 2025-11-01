WITH cohort AS (
  SELECT 
    p.subject_id, 
    i.stay_id, 
    i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),
first_map AS (
  SELECT 
    c.stay_id, 
    ce.charttime, 
    ce.valuenum AS map_value
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON c.subject_id = ce.subject_id 
    AND c.stay_id = ce.stay_id
  WHERE ce.itemid IN (52, 220052)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY ce.charttime ASC) = 1
)
SELECT 
  PERCENTILE_CONT(map_value, 0.25) OVER() AS q1,
  PERCENTILE_CONT(map_value, 0.75) OVER() AS q3,
  PERCENTILE_CONT(map_value, 0.75) OVER() - PERCENTILE_CONT(map_value, 0.25) OVER() AS iqr
FROM first_map
LIMIT 1;