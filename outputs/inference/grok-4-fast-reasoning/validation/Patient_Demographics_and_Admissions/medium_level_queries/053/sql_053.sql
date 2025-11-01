WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    CASE 
      WHEN a.discharge_location = 'DEAD/EXPIRED' THEN 'in-hospital death'
      WHEN a.discharge_location = 'HOSPICE' THEN 'hospice'
      WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
    END AS discharge_category
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admission_type = 'EMERGENCY'
    AND a.dischtime IS NOT NULL
    AND a.admittime < a.dischtime
)

SELECT 
  discharge_category,
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los_days,
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS iqr_q1,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS iqr_q3
FROM 
  cohort
WHERE 
  discharge_category IS NOT NULL
GROUP BY 
  discharge_category
ORDER BY 
  discharge_category;