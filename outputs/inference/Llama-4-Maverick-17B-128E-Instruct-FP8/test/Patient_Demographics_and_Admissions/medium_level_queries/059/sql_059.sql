WITH filtered_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.admission_location,
    a.hospital_expire_flag,  -- Added hospital_expire_flag here
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
),
discharge_categories AS (
  SELECT 
    subject_id,
    hadm_id,
    los_days,
    CASE 
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      WHEN discharge_location = 'DEAD/EXPIRED' OR hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE 'Other'
    END AS discharge_category
  FROM 
    filtered_patients
),
los_analysis AS (
  SELECT 
    discharge_category,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS patients_with_los_ge_7,
    APPROX_QUANTILES(los_days, 100)[OFFSET(70)] AS percentile_70_los  
  FROM 
    discharge_categories
  GROUP BY 
    discharge_category
)
SELECT 
  discharge_category,
  patients_with_los_ge_7 / total_patients AS proportion_los_ge_7,
  percentile_70_los
FROM 
  los_analysis
ORDER BY 
  discharge_category;