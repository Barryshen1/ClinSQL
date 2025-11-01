WITH filtered_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.dischtime IS NOT NULL
),
discharge_outcomes AS (
  SELECT 
    hadm_id,
    los_days,
    CASE
      WHEN discharge_location = 'HOME' THEN 'home'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'hospice'
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      ELSE 'other'
    END AS discharge_outcome
  FROM 
    filtered_admissions
)
SELECT 
  discharge_outcome,
  COUNT(*) AS count,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS std_los,
  SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS percent_le_10_days
FROM 
  discharge_outcomes
WHERE 
  discharge_outcome IN ('home', 'hospice', 'in-hospital death')
GROUP BY 
  discharge_outcome;