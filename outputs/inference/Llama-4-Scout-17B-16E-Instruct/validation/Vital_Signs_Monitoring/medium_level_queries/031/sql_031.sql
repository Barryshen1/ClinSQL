WITH 
  -- Filter patients and extract relevant data
  patients_data AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      ic.stay_id,
      ic.intime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
        ON p.subject_id = ic.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 67 AND 77
  ),
  
  -- Extract temperature data within the first 24 hours of ICU stay
  temperature_data AS (
    SELECT 
      cd.stay_id,
      cd.charttime,
      cd.valuenum AS temperature
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` cd
    WHERE 
      cd.itemid = 220050  -- Temperature itemid
      AND cd.valuenum IS NOT NULL
  ),
  
  -- Calculate average temperature per stay within the first 24 hours
  avg_temperatures AS (
    SELECT 
      td.stay_id,
      AVG(td.temperature) AS avg_temperature
    FROM 
      temperature_data td
    JOIN 
      patients_data pd 
        ON td.stay_id = pd.stay_id
    WHERE 
      td.charttime BETWEEN pd.intime AND TIMESTAMP_ADD(pd.intime, INTERVAL 24 HOUR)
    GROUP BY 
      td.stay_id
  )

-- Calculate percentile of 36.0°C in average temperatures
SELECT 
  COUNT(*) AS total_stays,
  SUM(CASE WHEN avg_temperature <= 36.0 THEN 1 ELSE 0 END) * 100 / COUNT(*) AS percentile
FROM 
  avg_temperatures;