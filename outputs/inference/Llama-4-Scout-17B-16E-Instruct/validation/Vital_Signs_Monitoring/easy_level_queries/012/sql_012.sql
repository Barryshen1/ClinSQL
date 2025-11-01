WITH 
  -- Identify itemid for diastolic blood pressure
  diastolic_bp_itemid AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label LIKE '%Diastolic Blood Pressure%'
  ),
  
  -- Filter patients and stays
  patient_stays AS (
    SELECT 
      ic.stay_id,
      ic.subject_id,
      p.anchor_age,
      p.gender,
      ic.first_careunit
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON ic.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 49 AND 59
      AND ic.first_careunit IN ('IMC', 'SD')  -- Assuming IMC and SD are step-down units
  ),
  
  -- Extract diastolic BP for each stay
  stay_diastolic_bp AS (
    SELECT 
      ps.stay_id,
      AVG(cv.valuenum) AS mean_diastolic_bp
    FROM 
      patient_stays ps
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` cv 
      ON ps.stay_id = cv.stay_id
    WHERE 
      cv.itemid IN (SELECT itemid FROM diastolic_bp_itemid)
    GROUP BY 
      ps.stay_id
  )

-- Calculate IQR of mean diastolic BP
SELECT 
  Q3 - Q1 AS iqr_mean_diastolic_bp
FROM (
  SELECT 
    PERCENTILE_CONT(0.75) OVER () AS Q3,
    PERCENTILE_CONT(0.25) OVER () AS Q1
  FROM 
    stay_diastolic_bp
);