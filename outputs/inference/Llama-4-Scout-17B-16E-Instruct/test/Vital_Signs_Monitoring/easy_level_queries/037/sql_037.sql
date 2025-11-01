WITH 
  -- Get itemid for MAP
  map_itemid AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label = 'Mean Arterial Pressure'
  ),
  
  -- Filter patients and get their ICU stays
  patients_stays AS (
    SELECT p.subject_id, p.anchor_age, p.gender, ic.stay_id, ic.intime 
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p 
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON p.subject_id = ic.subject_id 
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 89 AND 99
  ),
  
  -- Get MAP measurements within the first 24 hours of ICU stay
  map_measurements AS (
    SELECT ps.subject_id, ps.stay_id, 
           TIMESTAMP_ADD(ps.intime, INTERVAL 1 DAY) AS end_time,
           ce.charttime, 
           ce.valuenum 
    FROM patients_stays ps 
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON ps.subject_id = ce.subject_id AND ps.stay_id = ce.stay_id 
    CROSS JOIN map_itemid mi 
    WHERE ce.itemid = mi.itemid 
      AND ce.charttime BETWEEN ps.intime AND TIMESTAMP_ADD(ps.intime, INTERVAL 1 DAY)
  )

-- Calculate average MAP
SELECT AVG(valuenum) AS avg_map
FROM map_measurements;