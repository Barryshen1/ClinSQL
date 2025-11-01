WITH 
  -- Filter patients and extract temperature data
  patient_data AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      ic.stay_id,
      ic.intime,
      ic.outtime,
      cv.valueuom,
      cv.valuenum
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ic.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` cv 
        ON ic.stay_id = cv.stay_id 
        AND cv.itemid = 220050  -- Temperature itemid
    WHERE 
      p.anchor_age BETWEEN 85 AND 95
      AND p.gender = 'M'
  ),

  -- Calculate average temperature for each ICU stay
  avg_temp AS (
    SELECT 
      stay_id,
      AVG(valuenum) AS avg_temp
    FROM 
      patient_data
    GROUP BY 
      stay_id
  )

-- Calculate percentile rank
SELECT 
  APPROX_PERCENTILE_CONT(0.5) OVER (ORDER BY avg_temp) AS median,
  PERCENT_RANK() OVER (ORDER BY avg_temp) AS percentile_rank,
  COUNT(*) AS total_stays,
  SUM(CASE WHEN avg_temp <= 36.0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile_rank_custom
FROM 
  avg_temp;