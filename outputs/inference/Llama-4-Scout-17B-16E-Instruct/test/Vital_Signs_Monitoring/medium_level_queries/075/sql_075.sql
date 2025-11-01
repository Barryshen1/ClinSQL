WITH 
  -- Get patient demographics
  patient_info AS (
    SELECT 
      p.subject_id, 
      p.gender, 
      p.anchor_age
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE 
      p.gender = 'M' AND 
      p.anchor_age BETWEEN 56 AND 66
  ),
  
  -- Get ICU stay information
  icu_stays AS (
    SELECT 
      i.subject_id, 
      i.hadm_id, 
      i.stay_id, 
      i.intime, 
      i.outtime
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      patient_info p ON i.subject_id = p.subject_id
  ),
  
  -- Get blood pressure readings
  bp_readings AS (
    SELECT 
      ce.subject_id, 
      ce.hadm_id, 
      ce.stay_id, 
      ce.charttime, 
      ce.itemid, 
      ce.valuenum
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE 
      ce.itemid IN (220050, 220179)  -- Diastolic and Systolic BP
  ),
  
  -- Calculate MAP for each reading
  map_values AS (
    SELECT 
      bp.stay_id,
      bp.charttime,
      CASE 
        WHEN bp.itemid = 220050 THEN (2 * bp.valuenum + 
                                      (SELECT 
                                         valuenum 
                                       FROM 
                                         bp_readings 
                                       WHERE 
                                         stay_id = bp.stay_id AND 
                                         charttime = bp.charttime AND 
                                         itemid = 220179)) / 3 
        WHEN bp.itemid = 220179 THEN ((2 * 
                                      (SELECT 
                                         valuenum 
                                       FROM 
                                         bp_readings 
                                       WHERE 
                                         stay_id = bp.stay_id AND 
                                         charttime = bp.charttime AND 
                                         itemid = 220050)) + bp.valuenum) / 3 
      END AS map_value
    FROM 
      bp_readings bp
  ),
  
  -- Get mean MAP for each stay
  mean_map AS (
    SELECT 
      stay_id, 
      AVG(map_value) AS mean_map_value
    FROM 
      map_values
    GROUP BY 
      stay_id
  ),
  
  -- Categorize MAP
  map_categories AS (
    SELECT 
      stay_id, 
      mean_map_value,
      CASE 
        WHEN mean_map_value < 65 THEN '<65'
        WHEN mean_map_value BETWEEN 65 AND 74 THEN '65-74'
        WHEN mean_map_value BETWEEN 75 AND 84 THEN '75-84'
        ELSE '>=85'
      END AS map_category
    FROM 
      mean_map
  ),
  
  -- Get stroke information
  stroke_info AS (
    SELECT 
      di.hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code
    WHERE 
      d.long_title LIKE '%Stroke%'
  )

-- Final query
SELECT 
  mc.map_category, 
  COUNT(DISTINCT mc.stay_id) AS patient_count,
  SUM(CASE 
        WHEN si.hadm_id IS NOT NULL THEN 1 
        ELSE 0 
      END) AS stroke_count,
  SUM(CASE 
        WHEN si.hadm_id IS NOT NULL THEN 1 
        ELSE 0 
      END) / COUNT(DISTINCT mc.stay_id) AS stroke_rate
FROM 
  map_categories mc
LEFT JOIN 
  icu_stays i ON mc.stay_id = i.stay_id
LEFT JOIN 
  stroke_info si ON i.hadm_id = si.hadm_id
GROUP BY 
  mc.map_category;