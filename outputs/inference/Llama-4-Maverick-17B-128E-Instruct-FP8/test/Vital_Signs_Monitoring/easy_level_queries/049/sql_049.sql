WITH patient_cohort AS (
  SELECT p.subject_id, ie.stay_id, p.anchor_age, ie.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 85 AND 95
),
map_measurements AS (
  SELECT pc.subject_id, pc.stay_id, AVG(ce.valuenum) AS avg_map
  FROM patient_cohort pc
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON pc.stay_id = ce.stay_id
  WHERE ce.itemid = 220052  
  AND ce.charttime BETWEEN pc.intime AND TIMESTAMP_ADD(pc.intime, INTERVAL 24 HOUR)
  GROUP BY pc.subject_id, pc.stay_id
)
SELECT STDDEV(avg_map) AS std_dev_map
FROM map_measurements;