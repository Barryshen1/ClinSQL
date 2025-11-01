WITH patient_data AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    s.curr_service,
    p.anchor_age,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.services` s ON a.hadm_id = s.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 49 AND 59
    AND s.curr_service = 'Medicine'
),
discharge_status AS (
  SELECT 
    hadm_id,
    los,
    CASE 
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE 'Other'
    END AS discharge_status
  FROM 
    patient_data
)
SELECT 
  ds.discharge_status,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN ds.los >= 7 THEN 1 ELSE 0 END) / COUNT(*) AS proportion_los_ge_7,
  SUM(CASE WHEN ds.los >= 14 THEN 1 ELSE 0 END) / COUNT(*) AS proportion_los_ge_14,
  APPROX_QUANTILES(ds.los, 100)[OFFSET(70)] AS percentile_70_los
FROM 
  discharge_status ds
WHERE 
  ds.discharge_status IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY 
  ds.discharge_status;