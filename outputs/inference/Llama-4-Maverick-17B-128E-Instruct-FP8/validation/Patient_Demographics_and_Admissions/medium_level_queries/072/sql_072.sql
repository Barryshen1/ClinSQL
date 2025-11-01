WITH 
-- Calculate age at admission and filter population
patient_age AS (
  SELECT 
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.deathtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
),

-- Identify medicine inpatients
medicine_patients AS (
  SELECT 
    pa.hadm_id,
    pa.age_at_admission,
    pa.admittime,
    pa.dischtime,
    pa.discharge_location,
    pa.deathtime,
    pa.hospital_expire_flag,
    s.curr_service
  FROM 
    patient_age pa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.services` s ON pa.hadm_id = s.hadm_id
  WHERE 
    pa.gender = 'M'
    AND pa.age_at_admission BETWEEN 74 AND 84
    AND s.curr_service = 'Medicine'
),

-- Calculate LOS and discharge status
los_discharge_status AS (
  SELECT 
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los,
    CASE 
      WHEN discharge_location LIKE '%HOME%' THEN 'Home'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_status,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital Death'
      ELSE 'Not In-hospital Death'
    END AS death_status
  FROM 
    medicine_patients
),

-- Final categorization and calculation
final_data AS (
  SELECT 
    los,
    CASE 
      WHEN discharge_status = 'Home' AND death_status = 'Not In-hospital Death' THEN 'Discharge Home'
      WHEN discharge_status = 'Hospice' AND death_status = 'Not In-hospital Death' THEN 'Hospice'
      WHEN death_status = 'In-hospital Death' THEN 'In-hospital Death'
      ELSE 'Other'
    END AS final_status
  FROM 
    los_discharge_status
)

-- Aggregate results
SELECT 
  final_status,
  COUNT(*) AS count,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  SUM(IF(los <= 5, 1, 0)) / COUNT(*) AS proportion_los_leq_5
FROM 
  final_data
WHERE 
  final_status IN ('Discharge Home', 'Hospice', 'In-hospital Death')
GROUP BY 
  final_status
ORDER BY 
  final_status;