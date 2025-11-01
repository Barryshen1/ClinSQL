WITH 
  -- Filter patients by age and gender
  patients AS (
    SELECT 
      p.subject_id, 
      p.anchor_age, 
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 37 AND 47
  ),

  -- Extract temperature data
  temperatures AS (
    SELECT 
      ce.stay_id, 
      AVG(ce.valuenum) AS mean_temp
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE 
      ce.itemid IN (220050, 220179)  -- oral or body temperature
      AND ce.valuenum IS NOT NULL
    GROUP BY 
      ce.stay_id
  ),

  -- Join patients and temperature data with icustays
  icu_stays AS (
    SELECT 
      p.subject_id, 
      s.stay_id, 
      t.mean_temp
    FROM 
      patients p
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` s 
        ON p.subject_id = s.subject_id
    JOIN 
      temperatures t 
        ON s.stay_id = t.stay_id
  )

-- Calculate 75th percentile of mean temperature per stay
SELECT 
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY mean_temp) AS percentile_75
FROM 
  icu_stays;