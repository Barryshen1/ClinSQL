WITH 
  -- Filter and calculate LOS for relevant patients
  patient_stay AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 68 AND 78
      AND a.admission_location = 'ED'
  )
  
SELECT 
  hospital_expire_flag AS discharge_status,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los,
  COUNT(CASE WHEN los_days <= 7 THEN 1 END) / COUNT(*) * 100 AS percent_los_leq_7_days
FROM 
  patient_stay
GROUP BY 
  hospital_expire_flag;