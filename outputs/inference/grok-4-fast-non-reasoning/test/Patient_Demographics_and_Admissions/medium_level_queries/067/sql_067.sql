WITH eligible_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    PERCENTILE_CONT(los_days, 0.7) OVER () AS los_7day_percentile,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location ILIKE 'HOME' THEN 'Home'
      WHEN a.discharge_location ILIKE 'HOSPICE' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_category
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND a.admission_location = 'MED-SICU'  -- Adjust if needed; common for medicine service
    AND a.dischtime > a.admittime
)

SELECT 
  discharge_category,
  COUNT(*) AS total_patients,
  ROUND(AVG(CASE WHEN los_days >= 7 THEN 1.0 ELSE 0 END) * 100, 2) AS prop_los_ge7_pct,
  ROUND(AVG(CASE WHEN los_days >= 14 THEN 1.0 ELSE 0 END) * 100, 2) AS prop_los_ge14_pct,
  ANY_VALUE(los_7day_percentile) AS los_7day_percentile
FROM eligible_patients
WHERE discharge_category IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY discharge_category
ORDER BY 
  CASE discharge_category
    WHEN 'Home' THEN 1
    WHEN 'Hospice' THEN 2
    WHEN 'In-hospital death' THEN 3
    ELSE 4
  END;