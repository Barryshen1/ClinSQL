WITH patient_data AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    a.admission_location
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.admission_location = 'ED'
),
los_data AS (
  SELECT 
    subject_id,
    hadm_id,
    hospital_expire_flag,
    DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) AS los
  FROM 
    patient_data
)
SELECT 
  hospital_expire_flag,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 0.5)[OFFSET(1)] AS median_los,
  COUNT(CASE WHEN los <= 5 THEN 1 END) / COUNT(*) * 100 AS percent_leq_5_day_los
FROM 
  los_data
GROUP BY 
  hospital_expire_flag;