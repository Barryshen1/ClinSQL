WITH 
  -- Calculate LOS and filter patients by age and gender
  patient_stays AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      a.admittime,
      a.dischtime,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.anchor_age BETWEEN 64 AND 74
      AND p.gender = 'M'
  ),
  
  -- Determine discharge location
  discharge_location AS (
    SELECT 
      ps.subject_id,
      ps.hadm_id,
      ps.los,
      CASE 
        WHEN a.discharge_location = 'Home' THEN 'Home'
        WHEN a.discharge_location IN ('SNF', 'Rehab', 'LTACH') THEN 'SNF/rehab/LTACH'
        ELSE 'In-hospital death'
      END AS discharge_category
    FROM 
      patient_stays ps
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON ps.subject_id = a.subject_id AND ps.hadm_id = a.hadm_id
  )

-- Calculate proportion with LOS ≥ 7 days and 14-day percentile per group
SELECT 
  discharge_category,
  COUNT(CASE WHEN los >= 7 THEN 1 END) / COUNT(*) AS proportion_los_geq_7,
  APPROX_QUANTILES(los, 100)[OFFSET(14)] AS los_14th_percentile
FROM 
  discharge_location
GROUP BY 
  discharge_category;