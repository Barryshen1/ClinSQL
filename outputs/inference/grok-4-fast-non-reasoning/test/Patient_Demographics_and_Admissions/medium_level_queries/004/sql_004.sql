WITH filtered_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admission_type = 'ELECTIVE'
    AND a.dischtime > a.admittime  -- Valid LOS > 0
),
discharge_categories AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-Hospital Death'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LONG TERM CARE HOSPITAL') THEN 'Hospice/Other Facility'
      WHEN discharge_location IN ('HOME', 'SELF') THEN 'Home'
      ELSE 'Hospice/Other Facility'  -- Default non-home living discharges
    END AS discharge_category
  FROM 
    filtered_admissions
  WHERE 
    los_days > 0  -- Exclude zero/negative LOS
)
SELECT 
  discharge_category,
  COUNT(*) AS total_admissions,
  ROUND(AVG(los_days), 2) AS mean_los,
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS median_los,  -- p50
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS p75_los,
  APPROX_QUANTILES(los_days, 10)[OFFSET(8)] AS p90_los,  -- 90th percentile
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN los_days < 5 THEN 1 ELSE 0 END), COUNT(*)) * 100, 2) AS pct_los_less_than_5_days
FROM 
  discharge_categories
GROUP BY 
  discharge_category
ORDER BY 
  CASE discharge_category
    WHEN 'Home' THEN 1
    WHEN 'Hospice/Other Facility' THEN 2
    WHEN 'In-Hospital Death' THEN 3
  END;