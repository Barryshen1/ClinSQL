WITH 
  -- Filter patients for males aged 48-58 and get their admissions
  target_patients AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp`.patients p
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 48 AND 58
  ),
  
  -- Get icustays for target patients
  target_icustays AS (
    SELECT 
      i.stay_id,
      i.subject_id,
      i.hadm_id,
      i.intime,
      i.outtime
    FROM 
      `physionet-data.mimiciv_3_1_icu`.icustays i
    JOIN 
      target_patients tp ON i.subject_id = tp.subject_id
  ),
  
  -- Get MAP measurements for target icustays
  map_measurements AS (
    SELECT 
      ce.stay_id,
      MAX(CASE 
        WHEN ce.itemid = 220050 AND ce.valuenum IS NOT NULL THEN ce.valuenum 
        ELSE NULL 
      END) AS max_map
    FROM 
      `physionet-data.mimiciv_3_1_icu`.chartevents ce
    JOIN 
      target_icustays ti ON ce.stay_id = ti.stay_id
    GROUP BY 
      ce.stay_id
  )

-- Calculate average of maximum MAPs
SELECT 
  AVG(max_map) AS avg_max_map
FROM 
  map_measurements;