WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admission_type != 'EMERGENCY'
),
discharge_categories AS (
  SELECT 
    hadm_id,
    los,
    CASE
      WHEN discharge_location LIKE '%HOME%' THEN 'Home'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN hospital_expire_flag = 1 THEN 'In-hospital Death'
      ELSE 'Other'
    END AS discharge_category
  FROM 
    patient_admissions
)
SELECT 
  discharge_category,
  COUNT(*) AS total_patients,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
  SUM(IF(los < 5, 1, 0)) / COUNT(*) * 100 AS percent_los_lt_5
FROM 
  discharge_categories
WHERE 
  discharge_category IN ('Home', 'Hospice', 'In-hospital Death')
GROUP BY 
  discharge_category
ORDER BY 
  discharge_category;