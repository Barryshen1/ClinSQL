WITH 
  -- Define discharge location categories
  discharge_categories AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      CASE
        WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
        WHEN a.discharge_location LIKE '%Home%' THEN 'Home'
        ELSE 'Facility'
      END AS discharge_location_category
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
  ),
  
  -- Calculate LOS for ICU stays
  icu_los AS (
    SELECT 
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      TIMESTAMP_DIFF(i.outtime, i.intime, DAY) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
  ),
  
  -- Combine patient demographics, ICU stays, and discharge categories
  patient_data AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      dc.discharge_location_category,
      il.los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN 
      discharge_categories dc ON a.subject_id = dc.subject_id AND a.hadm_id = dc.hadm_id
    JOIN 
      icu_los il ON a.subject_id = il.subject_id AND a.hadm_id = il.hadm_id
    WHERE 
      p.gender = 'F' AND p.anchor_age BETWEEN 87 AND 97
  )

-- Final analysis
SELECT 
  discharge_location_category,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los,
  SUM(CASE WHEN los_days < 10 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS percent_los_lt_10_days
FROM 
  patient_data
GROUP BY 
  discharge_location_category;