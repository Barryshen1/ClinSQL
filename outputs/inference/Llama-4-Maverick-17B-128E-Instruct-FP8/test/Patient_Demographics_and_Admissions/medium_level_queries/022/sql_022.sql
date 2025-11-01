WITH filtered_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
    AND a.hadm_id IS NOT NULL
),
discharge_status AS (
  SELECT 
    hadm_id,
    los_days,
    CASE
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE 'Other'
    END AS discharge_category
  FROM 
    filtered_admissions
  WHERE 
    discharge_location IN ('HOME', 'HOSPICE') OR hospital_expire_flag = 1
)
SELECT 
  discharge_category,
  COUNT(*) AS count,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS percentile_75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS percentile_90_los,
  SUM(IF(los_days <= 10, 1, 0)) / COUNT(*) * 100 AS percent_los_le_10
FROM 
  discharge_status
GROUP BY 
  discharge_category
ORDER BY 
  discharge_category;