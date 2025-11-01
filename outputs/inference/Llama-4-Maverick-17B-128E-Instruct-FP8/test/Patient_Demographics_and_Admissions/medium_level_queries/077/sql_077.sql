WITH filtered_admissions AS (
  SELECT 
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND (p.anchor_year + p.anchor_age) BETWEEN (EXTRACT(YEAR FROM a.admittime) - 51) AND (EXTRACT(YEAR FROM a.admittime) - 41)
),
los_stats AS (
  SELECT 
    CASE WHEN deathtime IS NOT NULL THEN 'Deceased' ELSE 'Alive' END AS discharge_status,
    los_days,
    CASE WHEN los_days <= 5 THEN 1 ELSE 0 END AS los_le_5_days
  FROM 
    filtered_admissions
)
SELECT 
  discharge_status,
  COUNT(*) AS num_patients,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  (SUM(los_le_5_days) / COUNT(*)) * 100 AS percent_los_le_5_days
FROM 
  los_stats
GROUP BY 
  discharge_status;