WITH map_data AS (
  SELECT 
    c.stay_id,
    MAX(c.valuenum) OVER (PARTITION BY c.stay_id) AS max_map_per_stay
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id 
    AND c.hadm_id = i.hadm_id 
    AND c.stay_id = i.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE 
    c.itemid = 220052  -- MAP (Arterial Blood Pressure mean)
    AND c.valuenum IS NOT NULL
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND c.charttime >= i.intime 
    AND c.charttime <= i.outtime
)
SELECT 
  AVG(max_map_per_stay) AS avg_max_map
FROM map_data;