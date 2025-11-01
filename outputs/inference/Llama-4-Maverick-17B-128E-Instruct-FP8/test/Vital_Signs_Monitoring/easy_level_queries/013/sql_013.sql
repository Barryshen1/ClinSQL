WITH min_heart_rate AS (
  SELECT 
    MIN(ce.valuenum) AS min_hr
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND ce.itemid = 220050
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
)
SELECT 
  min_hr AS min_heart_rate
FROM 
  min_heart_rate;