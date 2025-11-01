WITH patient_data AS (
  SELECT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    a.admission_location,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN a.deathtime IS NULL THEN 'Alive' ELSE 'Died' END AS discharge_status
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 67 AND 77
),
stats AS (
  SELECT 
    discharge_status,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge_7,
    SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS los_ge_14,
    AVG(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) AS proportion_los_le_10
  FROM 
    patient_data
  GROUP BY 
    discharge_status
)
SELECT 
  discharge_status,
  total_patients,
  los_ge_7 / total_patients AS proportion_los_ge_7,
  los_ge_14 / total_patients AS proportion_los_ge_14,
  proportion_los_le_10
FROM 
  stats
ORDER BY 
  discharge_status;