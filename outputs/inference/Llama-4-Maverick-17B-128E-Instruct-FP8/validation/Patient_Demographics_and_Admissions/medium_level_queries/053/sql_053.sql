WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admission_type,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admission_type = 'EMERGENCY'
),
discharge_disposition AS (
  SELECT 
    hadm_id,
    los_days,
    CASE
      WHEN discharge_location LIKE '%HOME%' THEN 'home'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'hospice'
      WHEN deathtime BETWEEN admittime AND dischtime THEN 'in-hospital death'
      ELSE 'other'
    END AS discharge_category
  FROM 
    patient_admissions
)
SELECT 
  discharge_category,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS q1_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS q3_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS iqr_los
FROM 
  discharge_disposition
WHERE 
  discharge_category IN ('home', 'hospice', 'in-hospital death')
GROUP BY 
  discharge_category;