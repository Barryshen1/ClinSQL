WITH map_events AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    AVG(ce.valuenum) AS avg_map
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND ce.itemid IN (220052, 220181, 225312)  -- MAP itemids
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ie.intime
    AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY ie.stay_id, ie.subject_id, ie.hadm_id
)
SELECT 
  AVG(avg_map) AS overall_avg_map
FROM map_events;