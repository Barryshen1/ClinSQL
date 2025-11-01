WITH icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 39 AND 49
)
SELECT MIN(ce.valuenum) AS min_respiratory_rate
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
INNER JOIN icu_stays i ON ce.stay_id = i.stay_id
WHERE ce.itemid = 220210  
AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR);