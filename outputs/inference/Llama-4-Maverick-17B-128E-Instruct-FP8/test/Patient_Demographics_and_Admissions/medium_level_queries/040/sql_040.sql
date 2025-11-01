WITH patient_info AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 70 AND 80
),
surgical_patients AS (
  SELECT DISTINCT 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
),
los_and_disposition AS (
  SELECT 
    pi.hadm_id,
    DATETIME_DIFF(pi.dischtime, pi.admittime, DAY) AS los,
    CASE 
      WHEN pi.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN pi.discharge_location = 'HOME' THEN 'Home'
      WHEN pi.discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB', 'LONG TERM CARE HOSPITAL') THEN 'Facility'
      ELSE 'Other'
    END AS discharge_disposition
  FROM 
    patient_info pi
  INNER JOIN 
    surgical_patients sp ON pi.hadm_id = sp.hadm_id
)
SELECT 
  discharge_disposition,
  COUNT(*) AS total_count,
  SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) AS los_ge_7_count,
  SUM(CASE WHEN los >= 14 THEN 1 ELSE 0 END) AS los_ge_14_count,
  SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) / COUNT(*) AS proportion_los_ge_7,
  SUM(CASE WHEN los >= 14 THEN 1 ELSE 0 END) / COUNT(*) AS proportion_los_ge_14
FROM 
  los_and_disposition
GROUP BY 
  discharge_disposition;