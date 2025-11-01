WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    s.curr_service,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.services` s ON a.hadm_id = s.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND s.curr_service = 'Medicine'
),
discharge_disposition AS (
  SELECT 
    hadm_id,
    los_days,
    CASE
      WHEN deathtime IS NOT NULL THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM 
    filtered_admissions
)
SELECT 
  discharge_category,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS percentile_75,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS percentile_90,
  AVG(IF(los_days <= 10, 1, 0)) * 100 AS percent_le_10_days
FROM 
  discharge_disposition
GROUP BY 
  discharge_category
ORDER BY 
  discharge_category;