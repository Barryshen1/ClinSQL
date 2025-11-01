WITH filtered_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'hospice'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'home'
    END AS discharge_category
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.admission_location = 'HOSPITAL TRANSFER'
    AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
    AND a.hadm_id IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND (
      a.hospital_expire_flag = 1 
      OR LOWER(a.discharge_location) LIKE '%hospice%'
      OR LOWER(a.discharge_location) LIKE '%home%'
    )
)
SELECT 
  discharge_category,
  ROUND(AVG(los), 2) AS mean_los_days,
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS p25_los_days,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50_los_days,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los_days,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los_days,
  ROUND(100.0 * AVG(CASE WHEN los <= 10 THEN 1.0 ELSE 0.0 END), 2) AS pct_los_le10_days
FROM 
  filtered_admissions
WHERE 
  discharge_category IS NOT NULL
GROUP BY 
  discharge_category
ORDER BY 
  discharge_category;