WITH 
  -- Define a CTE to calculate LOS and filter patients
  patient_stays AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      p.gender,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      a.discharge_location,
      TIMESTAMPDIFF(DAY, a.admittime, a.dischtime) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 75 AND 85
  ),
  
  -- Categorize discharge locations
  discharge_categories AS (
    SELECT 
      subject_id,
      hadm_id,
      los,
      hospital_expire_flag,
      discharge_location,
      CASE 
        WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
        WHEN discharge_location LIKE '%Home%' THEN 'Discharged home'
        ELSE 'Discharged to facility'
      END AS discharge_category
    FROM 
      patient_stays
  )

-- Calculate proportion with LOS ≥ 7 days and percentile rank
SELECT 
  discharge_category,
  COUNT(CASE WHEN los >= 7 THEN 1 END) AS count_los_7_or_more,
  COUNT(*) AS total_patients,
  COUNT(CASE WHEN los >= 7 THEN 1 END) / COUNT(*) AS proportion_los_7_or_more,
  APPROX_QUANTILES(los, 1000)[70] AS percentile_70_los
FROM 
  discharge_categories
WHERE 
  discharge_category IN ('Discharged home', 'Discharged to facility', 'In-hospital death')
GROUP BY 
  discharge_category;