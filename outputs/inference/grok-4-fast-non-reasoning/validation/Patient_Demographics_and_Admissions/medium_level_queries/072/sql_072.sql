WITH filtered_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    a.hospital_expire_flag,
    a.discharge_location,
    a.admission_type,
    a.admission_location
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.admission_type = 'MED'
    AND a.admission_location IN ('EMERGENCY ROOM', 'PHYSICIAN REFERRAL', 'TRANSFER FROM HOSP')
    AND a.dischtime > a.admittime  -- Valid LOS
),
stratified_data AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%Hosp%' THEN 'Hospice'
      WHEN discharge_location IN ('Disch home', 'Home', 'Self', 'Disch home w home health svc') THEN 'Discharge home'
      ELSE NULL  -- Exclude other categories
    END AS discharge_group
  FROM 
    filtered_admissions
  WHERE 
    los_days IS NOT NULL
)
SELECT 
  discharge_group,
  COUNT(*) OVER (PARTITION BY discharge_group) AS n_admissions,
  AVG(los_days) OVER (PARTITION BY discharge_group) AS mean_los_days,
  PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY discharge_group) AS median_los_days,
  SAFE_DIVIDE(
    SUM(CASE WHEN los_days <= 5 THEN 1.0 ELSE 0 END) OVER (PARTITION BY discharge_group), 
    COUNT(*) OVER (PARTITION BY discharge_group)
  ) AS prop_los_le_5_days
FROM 
  stratified_data
WHERE 
  discharge_group IS NOT NULL
ORDER BY 
  discharge_group;