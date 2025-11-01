WITH 
  -- Define temperature categories
  temperature_categories AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      charttime,
      valuenum AS temperature,
      CASE 
        WHEN valuenum < 36.0 THEN '<36.0'
        WHEN valuenum BETWEEN 36.0 AND 37.9 THEN '36.0–37.9'
        WHEN valuenum >= 38.0 THEN '≥38.0'
      END AS temperature_category
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE 
      itemid = 220050  -- Temperature itemid
      AND valuenum IS NOT NULL
  ),
  
  -- Identify AKI patients (simplified, actual AKI detection may require more complex criteria)
  aki_patients AS (
    SELECT DISTINCT 
      subject_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE 
      itemid = 220052  -- Creatinine itemid
      AND valuenum > 1.5  -- Simplified AKI criteria
  ),
  
  -- Patient demographics and ICU stay
  patient_info AS (
    SELECT 
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      i.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 62 AND 72
  )

-- Main query
SELECT 
  temperature_category,
  COUNT(DISTINCT subject_id) AS number_of_patients,
  AVG(measurement_count) AS mean_measurements,
  APPROX_QUANTILES(measurement_count, 100)[SAFE_OFFSET(50)] AS median_measurements,
  APPROX_QUANTILES(measurement_count, 100)[SAFE_OFFSET(25)] AS q1_measurements,
  APPROX_QUANTILES(measurement_count, 100)[SAFE_OFFSET(75)] AS q3_measurements,
  SUM(CASE WHEN subject_id IN (SELECT subject_id FROM aki_patients) THEN 1 ELSE 0 END) / COUNT(DISTINCT subject_id) AS aki_rate
FROM (
  SELECT 
    pi.subject_id,
    tc.temperature_category,
    COUNT(tc.temperature) AS measurement_count
  FROM 
    patient_info pi
  JOIN 
    temperature_categories tc
  ON 
    pi.subject_id = tc.subject_id
    AND pi.hadm_id = tc.hadm_id
    AND pi.stay_id = tc.stay_id
    AND tc.charttime BETWEEN pi.intime AND TIMESTAMP_ADD(pi.intime, INTERVAL 1 DAY)
  GROUP BY 
    pi.subject_id, tc.temperature_category
) AS subquery
GROUP BY 
  temperature_category;