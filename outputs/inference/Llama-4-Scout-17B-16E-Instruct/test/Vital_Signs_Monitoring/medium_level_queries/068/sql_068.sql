WITH 
  -- Get relevant patient and ICU stay information
  patient_info AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      ic.stay_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp`.patients p
    JOIN 
      `physionet-data.mimiciv_3_1_icu`.icustays ic 
        ON p.subject_id = ic.subject_id
    WHERE 
      p.gender = 'F' AND 
      p.anchor_age BETWEEN 41 AND 51
  ),
  
  -- Get MAP measurements
  map_measurements AS (
    SELECT 
      pi.subject_id,
      pi.stay_id,
      CASE 
        WHEN ce.valuenum IS NOT NULL THEN ce.valuenum
        ELSE NULL
      END AS map_value
    FROM 
      patient_info pi
    JOIN 
      `physionet-data.mimiciv_3_1_icu`.chartevents ce 
        ON pi.subject_id = ce.subject_id AND pi.stay_id = ce.stay_id
    WHERE 
      ce.itemid = 220050 
  ),
  
  -- Categorize MAP
  map_categories AS (
    SELECT 
      subject_id,
      stay_id,
      map_value,
      CASE 
        WHEN map_value < 65 THEN '<65'
        WHEN map_value BETWEEN 65 AND 74 THEN '65-74'
        WHEN map_value BETWEEN 75 AND 84 THEN '75-84'
        WHEN map_value >= 85 THEN '>=85'
        ELSE 'Unknown'
      END AS map_category
    FROM 
      map_measurements
  ),
  
  -- Identify stroke patients
  stroke_patients AS (
    SELECT 
      di.subject_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    WHERE 
      di.icd_code LIKE 'I60%' OR 
      di.icd_code LIKE 'I61%' OR 
      di.icd_code LIKE 'I62%' OR 
      di.icd_code LIKE 'I63%' OR 
      di.icd_code LIKE 'I64%'
  )

-- Calculate patient counts and stroke rates for each MAP category
SELECT 
  mc.map_category,
  COUNT(DISTINCT mc.subject_id) AS patient_count,
  SUM(CASE WHEN sp.subject_id IS NOT NULL THEN 1 ELSE 0 END) AS stroke_count,
  SUM(CASE WHEN sp.subject_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(DISTINCT mc.subject_id) AS stroke_rate
FROM 
  map_categories mc
  LEFT JOIN stroke_patients sp ON mc.subject_id = sp.subject_id
GROUP BY 
  mc.map_category
ORDER BY 
  mc.map_category;