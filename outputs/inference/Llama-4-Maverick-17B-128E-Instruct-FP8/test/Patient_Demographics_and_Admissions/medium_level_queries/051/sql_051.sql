WITH 
filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
),
admission_details AS (
  SELECT 
    hadm_id,
    hospital_expire_flag,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM 
    filtered_admissions
)
SELECT 
  hospital_expire_flag AS discharge_status,
  COUNT(*) AS num_patients,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS std_los,
  SUM(IF(los_days <= 7, 1, 0)) / COUNT(*) * 100 AS percent_los_le_7
FROM 
  admission_details
GROUP BY 
  hospital_expire_flag
ORDER BY 
  discharge_status;