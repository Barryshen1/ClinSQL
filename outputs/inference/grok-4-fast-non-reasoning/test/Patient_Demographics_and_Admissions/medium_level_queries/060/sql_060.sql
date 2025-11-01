WITH filtered_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.admission_type,
    p.gender,
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.admission_type != 'OBSERVATION'
    AND a.dischtime > a.admittime  -- Ensure positive LOS
    AND a.discharge_location IN ('HOME', 'REHAB/DME', 'HOSPICE', 'DEAD/EXPIRED')
)
SELECT 
  CASE 
    WHEN discharge_location IN ('HOME', 'REHAB/DME') THEN 'Home'
    WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
    WHEN discharge_location = 'DEAD/EXPIRED' THEN 'In-hospital death'
  END AS discharge_outcome,
  AVG(los) AS mean_los_days,
  STDDEV(los) AS sd_los_days,
  (SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS pct_los_le_10_days
FROM 
  filtered_admissions
WHERE 
  los > 0
GROUP BY 
  discharge_outcome
ORDER BY 
  CASE discharge_outcome
    WHEN 'Home' THEN 1
    WHEN 'Hospice' THEN 2
    WHEN 'In-hospital death' THEN 3
  END;