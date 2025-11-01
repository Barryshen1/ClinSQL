WITH 
  patient_info AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE 
      p.gender = 'M' AND p.anchor_age BETWEEN 73 AND 83
  ),
  
  spo2_measurements AS (
    SELECT 
      ce.subject_id,
      ce.stay_id,
      ce.charttime,
      ce.valuenum AS spo2_value
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      patient_info pi ON ce.subject_id = pi.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.stay_id = icu.stay_id
    WHERE 
      ce.itemid = 220050  
      AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  ),
  
  mean_spo2 AS (
    SELECT 
      subject_id,
      AVG(spo2_value) AS mean_spo2
    FROM 
      spo2_measurements
    GROUP BY 
      subject_id
  )
SELECT 
  mean_spo2,
  PERCENT_RANK() OVER (ORDER BY mean_spo2) AS percentile
FROM 
  mean_spo2
ORDER BY 
  mean_spo2;