WITH cohort AS (
  SELECT 
      p.subject_id, 
      a.hadm_id,
      a.admittime,
      a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 82 AND 92
),
map_events AS (
  SELECT 
      c.hadm_id,
      ce.valuenum AS map_value
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.hadm_id = ce.hadm_id
      AND ce.charttime BETWEEN c.admittime AND c.dischtime
  WHERE 
      ce.itemid IN (220181, 225312)  -- MAP item IDs
      AND ce.valuenum IS NOT NULL
      AND ce.valuenum BETWEEN 20 AND 200  -- Valid MAP range
),
max_map_per_admission AS (
  SELECT 
      hadm_id,
      MAX(map_value) AS max_map
  FROM map_events
  GROUP BY hadm_id
)
SELECT DISTINCT
    PERCENTILE_CONT(max_map, 0.5) OVER() AS median_max_map
FROM max_map_per_admission;