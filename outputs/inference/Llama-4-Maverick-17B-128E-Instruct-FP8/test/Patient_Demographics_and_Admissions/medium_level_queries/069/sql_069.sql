WITH patient_data AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 59 AND 69 
    AND a.admission_type = 'EMERGENCY'
    AND a.hadm_id IN (SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.services` WHERE curr_service IN ('MED', 'Medicine'))
)
SELECT 
  'Proportion and Percentile' AS metric,
  hospital_expire_flag,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) AS patients_with_los_ge_7,
  SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) / COUNT(*) AS proportion_los_ge_7,
  (COUNTIF(los <= 7) / COUNT(*)) AS percentile_rank_7day_los
FROM 
  patient_data
GROUP BY 
  hospital_expire_flag;