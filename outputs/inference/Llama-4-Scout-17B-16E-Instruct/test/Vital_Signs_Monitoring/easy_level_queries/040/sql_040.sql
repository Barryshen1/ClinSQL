WITH 
-- Identify itemid for MAP
map_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE label = 'Mean Arterial Pressure'
),

-- Get first MAP for each ICU stay
first_map AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    MIN(ce.charttime) AS first_map_time,
    AVG(ce.valuenum) AS first_map_value
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON ie.subject_id = ce.subject_id 
      AND ie.hadm_id = ce.hadm_id 
      AND ie.stay_id = ce.stay_id
  JOIN 
    map_itemid mi 
      ON ce.itemid = mi.itemid
  WHERE 
    ce.valuenum IS NOT NULL 
    AND ie.intime < ce.charttime
  GROUP BY 
    ie.subject_id, ie.hadm_id, ie.stay_id
),

-- Filter target population
target_population AS (
  SELECT 
    a.subject_id,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
)

-- Calculate SD of first MAP
SELECT 
  STDDEV(first_map_value) AS sd_first_map
FROM 
  first_map fm
JOIN 
  target_population tp 
    ON fm.subject_id = tp.subject_id;