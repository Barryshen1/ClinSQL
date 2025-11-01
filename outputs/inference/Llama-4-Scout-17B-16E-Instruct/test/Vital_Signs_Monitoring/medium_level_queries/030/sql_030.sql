WITH 
  -- Identify female patients aged 81-91
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 81 AND 91
  ),
  
  -- Extract relevant ICU stays
  target_stays AS (
    SELECT stay_id, subject_id, intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE subject_id IN (SELECT subject_id FROM target_patients)
  ),
  
  -- Extract temperature readings from the first 24 hours of each ICU stay
  temperatures AS (
    SELECT 
      ce.stay_id,
      ce.valuenum AS temperature,
      TIMESTAMP_ADD(ts.intime, INTERVAL 1 HOUR) AS time_elapsed
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      target_stays ts ON ce.stay_id = ts.stay_id
    WHERE 
      ce.itemid = 220050  -- Temperature itemid
      AND ce.charttime BETWEEN ts.intime AND TIMESTAMP_ADD(ts.intime, INTERVAL 1 DAY)
  ),
  
  -- Calculate mean temperature for each stay
  stay_temperatures AS (
    SELECT 
      stay_id,
      AVG(temperature) AS mean_temperature
    FROM 
      temperatures
    GROUP BY 
      stay_id
  ),
  
  -- Classify mean temperatures
  classified_temperatures AS (
    SELECT 
      stay_id,
      mean_temperature,
      CASE 
        WHEN mean_temperature < 36.0 THEN '<36.0'
        WHEN mean_temperature BETWEEN 36.0 AND 37.9 THEN '36.0–37.9'
        ELSE '≥38.0'
      END AS temperature_category
    FROM 
      stay_temperatures
  ),
  
  -- Calculate statistics for mean temperatures
  statistics AS (
    SELECT 
      temperature_category,
      COUNT(stay_id) AS N,
      AVG(mean_temperature) AS mean,
      PERCENTILE_CONT(0.5)(mean_temperature) AS median,
      PERCENTILE_CONT(0.25)(mean_temperature) AS q1,
      PERCENTILE_CONT(0.75)(mean_temperature) AS q3
    FROM 
      classified_temperatures
    GROUP BY 
      temperature_category
  ),
  
  -- Calculate mortality rate
  mortality_rate AS (
    SELECT 
      COUNT(DISTINCT tp.subject_id) AS total_patients,
      SUM(CASE WHEN p.dod IS NOT NULL THEN 1 ELSE 0 END) AS deceased_patients
    FROM 
      target_patients tp
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p ON tp.subject_id = p.subject_id
  )

-- Final output
SELECT 
  s.temperature_category,
  s.N,
  s.mean,
  s.median,
  s.q3 - s.q1 AS IQR,
  100.0 * mr.deceased_patients / mr.total_patients AS mortality_rate
FROM 
  statistics s
CROSS JOIN 
  mortality_rate mr
ORDER BY 
  s.temperature_category;