WITH filtered_admissions AS (
  SELECT 
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_location = 'TRANSFER FROM OTHER HOSP'
    AND a.dischtime IS NOT NULL
),
classified_discharge AS (
  SELECT 
    los_days,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME CARE', 'HOME WITH HEALTH SERVICES', 'HOME WITH SERVICES', 'HOME HEALTH CARE') THEN 'Home'
      WHEN discharge_location IN ('HOSPICE', 'HOSPICE - HOME', 'HOSPICE - FACILITY') THEN 'Hospice'
      ELSE NULL
    END AS discharge_category
  FROM 
    filtered_admissions
  WHERE 
    discharge_location IS NOT NULL OR hospital_expire_flag = 1
),
proportions AS (
  SELECT 
    discharge_category,
    AVG(CASE WHEN los_days >= 7 THEN 1.0 ELSE 0 END) AS proportion_los_ge_7
  FROM 
    classified_discharge
  WHERE 
    discharge_category IS NOT NULL
  GROUP BY 
    discharge_category
),
p7_los AS (
  SELECT 
    PERCENTILE_CONT(los_days, 0.07) AS p7_los
  FROM 
    filtered_admissions
)
SELECT 
  discharge_category AS category,
  proportion_los_ge_7 AS value
FROM 
  proportions
UNION ALL
SELECT 
  'Overall 7th Percentile LOS' AS category,
  (SELECT p7_los FROM p7_los) AS value;