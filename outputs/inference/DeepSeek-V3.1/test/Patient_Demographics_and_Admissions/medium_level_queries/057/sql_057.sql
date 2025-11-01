WITH patient_cohort AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    p.anchor_age,
    p.gender,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(i.outtime, i.intime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
)

SELECT 
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
    WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
    WHEN discharge_location = 'HOME' THEN 'Home'
    ELSE 'Other' 
  END AS discharge_outcome,
  COUNT(*) AS n_patients,
  PERCENTILE_CONT(los_days, 0.50) OVER (PARTITION BY 
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      WHEN discharge_location = 'HOME' THEN 'Home'
      ELSE 'Other' 
    END) AS p50_los,
  PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY 
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      WHEN discharge_location = 'HOME' THEN 'Home'
      ELSE 'Other' 
    END) AS p75_los,
  PERCENTILE_CONT(los_days, 0.90) OVER (PARTITION BY 
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      WHEN discharge_location = 'HOME' THEN 'Home'
      ELSE 'Other' 
    END) AS p90_los,
  PERCENTILE_CONT(los_days, 0.95) OVER (PARTITION BY 
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      WHEN discharge_location = 'HOME' THEN 'Home'
      ELSE 'Other' 
    END) AS p95_los,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_lte_7_days
FROM patient_cohort
WHERE discharge_location IN ('HOME', 'HOSPICE') OR hospital_expire_flag = 1
GROUP BY discharge_outcome
ORDER BY discharge_outcome;