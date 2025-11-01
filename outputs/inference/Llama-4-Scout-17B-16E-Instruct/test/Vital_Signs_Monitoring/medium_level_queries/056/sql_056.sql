WITH 
  -- Define temperature measurements CTE
  temperature_measurements AS (
    SELECT 
      c.subject_id,
      c.hadm_id,
      c.stay_id,
      c.charttime,
      c.valuenum AS temperature,
      c.itemid
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` c
    WHERE 
      c.itemid IN (
        220050,  -- Temperature, Celsius
        220179   -- Temperature, Fahrenheit, converted to Celsius
      )
      AND c.valuenum IS NOT NULL
  ),

  -- Apply temperature conversion for Fahrenheit to Celsius
  temperature_measurements_converted AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      charttime,
      CASE 
        WHEN itemid = 220179 THEN (valuenum - 32) * 5.0/9.0
        ELSE valuenum
      END AS temperature
    FROM 
      temperature_measurements
  ),

  temperature_categories AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      charttime,
      temperature,
      CASE 
        WHEN temperature < 36 THEN '<36'
        WHEN temperature BETWEEN 36 AND 37.9 THEN '36–37.9'
        WHEN temperature >= 38 THEN '≥38'
      END AS temperature_category
    FROM 
      temperature_measurements_converted
  ),

  -- Patient demographic information
  patient_info AS (
    SELECT 
      subject_id,
      anchor_age,
      gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients`
  ),

  -- Calculate mortality rate
  mortality_info AS (
    SELECT 
      subject_id,
      hadm_id,
      hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions`
  )

SELECT 
  tc.temperature_category,
  COUNT(DISTINCT tc.subject_id) AS unique_patient_count,
  COUNT(tc.temperature) AS measurement_count,
  AVG(tc.temperature) AS mean_temperature,
  APPROX_QUANTILES(tc.temperature, 0.5)[OFFSET(1)] AS median_temperature,
  APPROX_QUANTILES(tc.temperature, 0.25)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(tc.temperature, 0.75)[OFFSET(1)] AS q3,
  APPROX_QUANTILES(tc.temperature, 0.75)[OFFSET(1)] - APPROX_QUANTILES(tc.temperature, 0.25)[OFFSET(1)] AS iqr,
  SUM(CASE WHEN mi.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT tc.subject_id) AS mortality_rate
FROM 
  temperature_categories tc
  JOIN patient_info pi ON tc.subject_id = pi.subject_id
  JOIN mortality_info mi ON tc.hadm_id = mi.hadm_id
WHERE 
  pi.anchor_age BETWEEN 89 AND 99
  AND pi.gender = 'F'
GROUP BY 
  tc.temperature_category;