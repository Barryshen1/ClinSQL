WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'hospice'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'home'
      ELSE 'other'
    END AS discharge_category
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admission_type != 'EMERGENCY'
    AND a.dischtime IS NOT NULL
    AND a.hadm_id IS NOT NULL
)
SELECT 
  discharge_category,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los_days,
  ROUND(AVG(CASE WHEN los_days < 5 THEN 1.0 ELSE 0 END) * 100, 2) AS pct_los_less_5_days
FROM 
  cohort
WHERE 
  discharge_category IN ('home', 'hospice', 'in-hospital death')
GROUP BY 
  discharge_category
ORDER BY 
  discharge_category;