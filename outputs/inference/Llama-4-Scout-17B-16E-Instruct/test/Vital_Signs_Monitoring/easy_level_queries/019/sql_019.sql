WITH 
  -- Filter patients by age and gender
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE anchor_age BETWEEN 73 AND 83
    AND gender = 'F'
  ),
  
  -- Identify step-down/IMC stays
  imc_stays AS (
    SELECT i.stay_id, i.subject_id, i.hadm_id, i.first_careunit, i.last_careunit
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN target_patients tp ON i.subject_id = tp.subject_id
    WHERE i.first_careunit IN ('IMC', 'SD')
  ),
  
  -- Get MAP measurements for these stays
  map_measurements AS (
    SELECT 
      ce.stay_id,
      AVG(ce.valuenum) AS mean_map
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN imc_stays ims ON ce.stay_id = ims.stay_id
    WHERE ce.itemid = 220050  -- Itemid for MAP
    GROUP BY ce.stay_id
  )

-- Calculate average MAP per stay
SELECT 
  AVG(mean_map) AS average_map
FROM map_measurements;