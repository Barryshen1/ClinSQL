WITH 
  patient_data AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      ic.stay_id,
      ic.hadm_id,
      ce.itemid,
      ce.charttime,
      ce.valuenum AS heart_rate
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ic.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON ic.stay_id = ce.stay_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 80 AND 90
      AND ce.itemid = 220050  -- Heart Rate
  ),
  
  avg_heart_rate_data AS (
    SELECT 
      subject_id,
      hadm_id,
      AVG(heart_rate) AS avg_heart_rate
    FROM 
      patient_data
    GROUP BY 
      subject_id, hadm_id
  )

SELECT 
  percentile
FROM (
  SELECT 
    avg_heart_rate,
    PERCENT_RANK() OVER (ORDER BY avg_heart_rate) AS percentile
  FROM 
    avg_heart_rate_data
)
WHERE 
  avg_heart_rate = 110;