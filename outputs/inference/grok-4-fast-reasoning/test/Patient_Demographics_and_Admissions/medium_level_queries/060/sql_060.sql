WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) > 0
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 50 AND 60
)
SELECT 
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
    WHEN discharge_location LIKE '%Hospice%' THEN 'hospice'
    WHEN discharge_location = 'Discharged to home' THEN 'home'
    ELSE NULL 
  END AS outcome,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS sd_los_days,
  ROUND((SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)), 2) AS percent_le10_days
FROM 
  cohort
WHERE 
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
    WHEN discharge_location LIKE '%Hospice%' THEN 'hospice'
    WHEN discharge_location = 'Discharged to home' THEN 'home'
    ELSE NULL 
  END IS NOT NULL
GROUP BY 
  outcome
ORDER BY 
  outcome;