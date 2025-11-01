WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Classify discharge category
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location LIKE '%HOSPICE%' THEN 'hospice'
      WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
      ELSE 'other'
    END AS discharge_category
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.admission_type != 'EMERGENCY'  -- Exclude emergency
    AND a.dischtime IS NOT NULL  -- Exclude ongoing admissions
),

stats AS (
  SELECT 
    discharge_category,
    COUNT(*) AS n_admissions,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
    SUM(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END) AS n_short_stay
  FROM patient_admissions
  WHERE discharge_category IN ('home', 'hospice', 'in-hospital death')
  GROUP BY discharge_category
)

SELECT 
  discharge_category,
  n_admissions,
  mean_los,
  p25_los,
  median_los,
  p75_los,
  p90_los,
  ROUND(100.0 * n_short_stay / n_admissions, 2) AS percent_los_leq_14
FROM stats
ORDER BY discharge_category;