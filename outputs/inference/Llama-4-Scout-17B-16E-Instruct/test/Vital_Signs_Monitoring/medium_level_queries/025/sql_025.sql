WITH 
  eligible_patients AS (
    SELECT p.subject_id, p.anchor_age, p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'M' AND p.anchor_age BETWEEN 82 AND 92
  ),
  
  eligible_stays AS (
    SELECT i.stay_id, i.subject_id, i.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN eligible_patients p ON i.subject_id = p.subject_id
  ),
  
  temperature_readings AS (
    SELECT c.stay_id, c.valuenum AS temperature
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN eligible_stays e ON c.stay_id = e.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
    WHERE d.label = 'Temperature (C)' AND c.charttime BETWEEN e.intime AND TIMESTAMP_ADD(e.intime, INTERVAL 24 HOUR)
  ),
  
  average_temperatures AS (
    SELECT stay_id, AVG(temperature) AS avg_temperature
    FROM temperature_readings
    GROUP BY stay_id
  )

SELECT 
  SUM(CASE WHEN avg_temperature <= 37.5 THEN 1 ELSE 0 END) / COUNT(*) AS percentile
FROM average_temperatures;