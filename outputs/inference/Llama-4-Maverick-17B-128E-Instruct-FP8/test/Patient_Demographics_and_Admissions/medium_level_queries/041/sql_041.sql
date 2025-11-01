WITH patient_info AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.anchor_age BETWEEN 88 AND 98
    AND p.gender = 'M'
    AND a.admission_type = 'ELECTIVE'  -- Elective admissions as a proxy for postoperative
),
discharge_outcome AS (
  SELECT 
    hadm_id,
    los_days,
    CASE
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB', 'LONG TERM CARE') THEN 'SNF/rehab/LTACH'
      ELSE 'Other'
    END AS discharge_category,
    hospital_expire_flag
  FROM 
    patient_info
),
final_discharge_data AS (
  SELECT 
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE discharge_category
    END AS final_discharge_category,
    CASE WHEN los_days <= 7 THEN 1 ELSE 0 END AS los_le_7
  FROM 
    discharge_outcome
  WHERE 
    discharge_category IN ('Home', 'SNF/rehab/LTACH', 'Other')  -- Filter here to keep the logic consistent
),
final_data AS (
  SELECT 
    final_discharge_category,
    los_days,
    los_le_7
  FROM 
    final_discharge_data
  WHERE 
    final_discharge_category IN ('Home', 'SNF/rehab/LTACH', 'In-hospital death')
)
SELECT 
  final_discharge_category,
  COUNT(*) AS n_patients,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  AVG(los_le_7) * 100 AS percent_los_le_7
FROM 
  final_data
GROUP BY 
  final_discharge_category
ORDER BY 
  final_discharge_category;