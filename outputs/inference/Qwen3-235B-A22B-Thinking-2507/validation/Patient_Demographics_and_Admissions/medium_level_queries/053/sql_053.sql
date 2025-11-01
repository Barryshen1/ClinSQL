WITH base AS (
  SELECT
    -- Calculate age at admission using MIMIC-IV's shifted timeline
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Compute exact LOS in fractional days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60.0) AS los_days,
    -- Define discharge categories per clinical question
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location = 'HOME' THEN 'discharged home'
      WHEN a.discharge_location LIKE '%HOSPICE%' THEN 'hospice'
      ELSE NULL
    END AS category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'  -- Female patients only
    AND a.admission_type = 'EMERGENCY'  -- Emergency admissions
    -- Age filter: 77-87 inclusive (using integer year approximation)
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 77 AND 87
)
SELECT
  category,
  -- Median LOS (50th percentile)
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median_los_days,
  -- IQR = Q3 - Q1 (75th - 25th percentile)
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] - APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS iqr_los_days
FROM base
WHERE category IS NOT NULL  -- Keep only the 3 target categories
GROUP BY category
-- Order results as specified in the clinical question
ORDER BY 
  CASE category
    WHEN 'discharged home' THEN 1
    WHEN 'hospice' THEN 2
    WHEN 'in-hospital death' THEN 3
  END;