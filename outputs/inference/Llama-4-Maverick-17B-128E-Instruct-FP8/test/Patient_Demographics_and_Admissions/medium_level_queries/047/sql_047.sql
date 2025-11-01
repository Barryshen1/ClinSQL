WITH patient_info AS (
  SELECT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
),
discharge_status AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB', 'HOSPICE') THEN 'Facility'
      WHEN hospital_expire_flag = 1 THEN 'Death'
      ELSE 'Other'
    END AS discharge_status
  FROM 
    patient_info
),
los_stats AS (
  SELECT 
    hospital_los_days
  FROM 
    patient_info
  INNER JOIN 
    discharge_status d ON patient_info.hadm_id = d.hadm_id
  WHERE 
    d.discharge_status IN ('Home', 'Facility', 'Death')
)
SELECT 
  AVG(hospital_los_days) AS mean_los,
  STDDEV(hospital_los_days) AS std_los,
  COUNTIF(hospital_los_days <= 5) * 1.0 / COUNT(*) AS percentile_rank_5day
FROM 
  los_stats;