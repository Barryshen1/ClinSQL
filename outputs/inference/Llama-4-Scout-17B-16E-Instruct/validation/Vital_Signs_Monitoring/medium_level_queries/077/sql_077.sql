WITH 
  patient_data AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      ic.stay_id,
      ic.hadm_id,
      ic.intime,
      ic.outtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
        ON p.subject_id = ic.subject_id
    WHERE 
      p.gender = 'F' AND 
      p.anchor_age BETWEEN 42 AND 52
  ),
  
  heart_rate_data AS (
    SELECT 
      pd.stay_id,
      ce.valuenum AS heart_rate
    FROM 
      patient_data pd
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON pd.stay_id = ce.stay_id
    WHERE 
      ce.itemid = 220050  -- Heart Rate
  ),
  
  avg_heart_rates AS (
    SELECT 
      stay_id,
      AVG(heart_rate) AS avg_heart_rate
    FROM 
      heart_rate_data
    GROUP BY 
      stay_id
  )

SELECT 
  COUNT(*) AS cohort_size,
  APPROX_PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY avg_heart_rate) AS percentile_90
FROM 
  avg_heart_rates;