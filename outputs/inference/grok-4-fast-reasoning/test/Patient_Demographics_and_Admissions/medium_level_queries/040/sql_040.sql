WITH base AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN a.discharge_location = 'DEAD/EXPIRE' THEN 'In-hospital death'
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_cat
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.admission_type = 'SURGICAL'
    AND a.dischtime IS NOT NULL
    AND a.discharge_location IN ('HOME', 'DEAD/EXPIRE', 'SNF', 'REHAB', 'LTAC')
)

SELECT 
  discharge_cat,
  COUNT(*) AS total_patients,
  COUNTIF(los_days >= 7) AS n_ge7,
  COUNTIF(los_days >= 14) AS n_ge14,
  ROUND(COUNTIF(los_days >= 7) * 100.0 / COUNT(*), 2) AS prop_ge7_pct,
  ROUND(COUNTIF(los_days >= 14) * 100.0 / COUNT(*), 2) AS prop_ge14_pct
FROM 
  base
GROUP BY 
  discharge_cat
ORDER BY 
  discharge_cat;