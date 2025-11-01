WITH patient_data AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 67 AND 77
),
discharge_status AS (
  SELECT 
    subject_id,
    hadm_id,
    los,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital Mortality'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Discharged Home'
      ELSE 'Discharged to Facility'
    END AS discharge_category
  FROM 
    patient_data
)
SELECT 
  discharge_category,
  AVG(los) AS mean_los,
  STDDEV(los) AS std_los,
  SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS percent_los_le_7
FROM 
  discharge_status
GROUP BY 
  discharge_category;