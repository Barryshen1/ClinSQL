WITH eligible_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.edregtime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.edregtime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.edregtime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.edregtime  -- Exclude invalid timestamps
),
outcomes AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN discharge_location LIKE '%HOME%' OR discharge_location LIKE '%DISCH%' THEN 'Discharged home'
      ELSE 'Other'
    END AS outcome
  FROM 
    eligible_admissions
  WHERE 
    (hospital_expire_flag = 1 
     OR discharge_location LIKE '%HOSPICE%' 
     OR (discharge_location LIKE '%HOME%' OR discharge_location LIKE '%DISCH%'))
)
SELECT 
  outcome,
  COUNT(*) AS n_patients,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los_days,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 10)[OFFSET(9)] AS p90_los_days,
  ROUND(AVG(CASE WHEN los_days <= 10 THEN 1.0 ELSE 0 END) * 100, 2) AS pct_le_10_days
FROM 
  outcomes
WHERE 
  outcome != 'Other'  -- Exclude non-matching discharges
GROUP BY 
  outcome
ORDER BY 
  CASE outcome
    WHEN 'Discharged home' THEN 1
    WHEN 'Hospice' THEN 2
    WHEN 'In-hospital death' THEN 3
  END;