WITH filtered_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location = 'HOME' THEN 'home'
      WHEN a.discharge_location = 'HOSPICE' THEN 'hospice'
      ELSE NULL  -- Exclude other outcomes
    END AS outcome_category
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.admission_type = 'ELECTIVE'
    AND a.dischtime > a.admittime  -- Complete admissions only
    AND a.dischtime IS NOT NULL
),
categorized_admissions AS (
  SELECT *
  FROM filtered_admissions
  WHERE outcome_category IS NOT NULL
)
SELECT DISTINCT
  outcome_category,
  COUNT(*) OVER (PARTITION BY outcome_category) AS total_cases,
  AVG(los_days) OVER (PARTITION BY outcome_category) AS mean_los_days,
  PERCENTILE_CONT(los_days, 0.25) OVER (PARTITION BY outcome_category) AS p25_los_days,
  PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY outcome_category) AS median_los_days,
  PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY outcome_category) AS p75_los_days,
  PERCENTILE_CONT(los_days, 0.9) OVER (PARTITION BY outcome_category) AS p90_los_days,
  SAFE_DIVIDE(
    SUM(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END) OVER (PARTITION BY outcome_category) * 100.0, 
    COUNT(*) OVER (PARTITION BY outcome_category)
  ) AS percent_le_14_days
FROM categorized_admissions
ORDER BY 
  total_cases DESC;