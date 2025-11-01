WITH 
  -- Get patient demographics
  patient_info AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      ic.intime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON p.subject_id = ic.subject_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 86 AND 96
  ),
  
  -- Get temperature measurements in the first 24 hours
  temp_measurements AS (
    SELECT 
      ce.valuenum AS temperature_value,
      ce.valueuom
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON ce.subject_id = ic.subject_id AND ce.hadm_id = ic.hadm_id AND ce.stay_id = ic.stay_id
    JOIN 
      patient_info pi 
      ON ce.subject_id = pi.subject_id
    WHERE 
      ce.itemid = 220050  -- Temperature itemid
      AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 24 HOUR)
  )

-- Calculate 75th percentile temperature in °F
SELECT 
  APPROX_QUANTILES(
    CASE 
      WHEN valueuom = '°F' THEN temperature_value
      WHEN valueuom = '°C' THEN (temperature_value * 9/5) + 32  -- Convert Celsius to Fahrenheit
    END, 4)  -- 75th percentile is the 3rd quantile out of 4 (index 3)
  WITHIN GROUP (ORDER BY 
    CASE 
      WHEN valueuom = '°F' THEN temperature_value
      WHEN valueuom = '°C' THEN (temperature_value * 9/5) + 32  
    END) AS percentile_temp
FROM 
  temp_measurements;