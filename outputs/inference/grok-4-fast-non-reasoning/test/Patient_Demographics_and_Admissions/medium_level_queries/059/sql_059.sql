WITH cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM (DATE(a.dischtime) - DATE(a.admittime))) AS los_days,
    a.discharge_location,
    a.hospital_expire_flag,
    a.admission_location
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_location = 'TRANSFER'
    AND a.dischtime IS NOT NULL
),

discharge_cats AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'DEATH'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'HOME'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'HOSPICE'
      ELSE 'OTHER'
    END AS discharge_cat
  FROM cohort
)

SELECT 
  discharge_cat,
  COUNT(*) AS n_patients,
  AVG(CASE WHEN los_days >= 7 THEN 1.0 ELSE 0 END) AS prop_los_ge7,
  PERCENTILE_CONT(los_days, 0.07) OVER (PARTITION BY discharge_cat) AS los_7th_percentile
FROM discharge_cats
WHERE discharge_cat IN ('HOME', 'HOSPICE', 'DEATH')
GROUP BY discharge_cat

UNION ALL

SELECT 
  'OVERALL' AS discharge_cat,
  COUNT(*) AS n_patients,
  AVG(CASE WHEN los_days >= 7 THEN 1.0 ELSE 0 END) AS prop_los_ge7,
  PERCENTILE_CONT(los_days, 0.07) AS los_7th_percentile
FROM discharge_cats
WHERE discharge_cat IN ('HOME', 'HOSPICE', 'DEATH')
ORDER BY 
  CASE discharge_cat 
    WHEN 'OVERALL' THEN 0 
    WHEN 'DEATH' THEN 1 
    WHEN 'HOSPICE' THEN 2 
    WHEN 'HOME' THEN 3 
  END
;