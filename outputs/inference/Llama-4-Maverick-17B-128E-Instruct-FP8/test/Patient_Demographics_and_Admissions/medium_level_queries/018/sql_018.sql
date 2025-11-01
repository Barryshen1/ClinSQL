WITH filtered_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
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
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
),
discharge_categories AS (
  SELECT 
    hadm_id,
    los_days,
    CASE 
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB/DISTINCT PART HOSP') THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE discharge_location
    END AS detailed_discharge_category
  FROM 
    filtered_admissions
),
categorized_discharge AS (
  SELECT 
    los_days,
    CASE 
      WHEN detailed_discharge_category = 'In-hospital death' THEN 'In-hospital death'
      WHEN discharge_category = 'Home' THEN 'Home'
      WHEN discharge_category = 'Facility' THEN 'Facility'
      ELSE 'Other'
    END AS final_discharge_category
  FROM 
    discharge_categories
)
SELECT 
  final_discharge_category,
  COUNT(*) AS total_patients,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS iqr_los,
  SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS percent_le_10_days
FROM 
  categorized_discharge
WHERE 
  final_discharge_category IN ('Home', 'Facility', 'In-hospital death')
GROUP BY 
  final_discharge_category
ORDER BY 
  final_discharge_category;