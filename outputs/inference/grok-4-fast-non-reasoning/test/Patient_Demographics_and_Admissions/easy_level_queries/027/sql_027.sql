WITH first_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    DATE(a.dischtime) - DATE(a.admittime) AS los_interval
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.dischtime IS NOT NULL
    AND a.deathtime IS NULL
    AND DATE(a.dischtime) > DATE(a.admittime)  -- Ensure positive LOS
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
)
SELECT 
  COUNT(*) AS num_patients,
  PERCENTILE_CONT(EXTRACT(DAY FROM los_interval), 0.25) OVER() AS q1_days,
  PERCENTILE_CONT(EXTRACT(DAY FROM los_interval), 0.75) OVER() AS q3_days,
  PERCENTILE_CONT(EXTRACT(DAY FROM los_interval), 0.75) OVER() - 
  PERCENTILE_CONT(EXTRACT(DAY FROM los_interval), 0.25) OVER() AS iqr_days
FROM first_admissions;