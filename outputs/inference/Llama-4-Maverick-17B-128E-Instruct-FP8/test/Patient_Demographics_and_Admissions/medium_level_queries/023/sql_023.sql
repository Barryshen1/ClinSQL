WITH cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
),
discharge_categories AS (
  SELECT 
    subject_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM 
    cohort
),
stats AS (
  SELECT 
    discharge_category,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS patients_with_los_ge_7
  FROM 
    discharge_categories
  GROUP BY 
    discharge_category
),
percentile_10_los AS (
  SELECT 
    discharge_category,
    PERCENTILE_CONT(los_days, 0.1) OVER (PARTITION BY discharge_category) AS percentile_10_los_value
  FROM 
    discharge_categories
)
SELECT 
  s.discharge_category,
  s.total_patients,
  s.patients_with_los_ge_7 / s.total_patients AS proportion_los_ge_7,
  pl.percentile_10_los_value
FROM 
  stats s
JOIN 
  (SELECT DISTINCT discharge_category, percentile_10_los_value FROM percentile_10_los) pl 
  ON s.discharge_category = pl.discharge_category;