WITH eligible_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.admission_location = 'HOSPITAL'
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0  -- Exclude invalid LOS
),
discharge_categories AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN discharge_location = 'HOME' THEN 'Home'
      ELSE 'Other'
    END AS discharge_category
  FROM 
    eligible_patients
)
SELECT 
  discharge_category,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 10)[OFFSET(2)] AS p25_los_days,
  APPROX_QUANTILES(los_days, 10)[OFFSET(5)] AS p50_los_days,
  APPROX_QUANTILES(los_days, 10)[OFFSET(7)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 10)[OFFSET(9)] AS p90_los_days,
  (SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS pct_los_le_10_days
FROM 
  discharge_categories
WHERE 
  discharge_category IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY 
  discharge_category
ORDER BY 
  discharge_category;