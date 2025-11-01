WITH 
  -- Filtered admissions
  filtered_admissions AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.admission_type,
      a.discharge_location,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 80 AND 90
      AND a.admission_type != 'EMERGENCY'
      AND a.dischtime IS NOT NULL
  ),
  
  -- Calculate LOS
  los_data AS (
    SELECT 
      hadm_id,
      admittime,
      dischtime,
      discharge_location,
      DATE_DIFF(dischtime, admittime, DAY) AS los
    FROM 
      filtered_admissions
  ),

  -- Discharge categories
  discharge_categories AS (
    SELECT 
      los,
      discharge_location,
      CASE 
        WHEN discharge_location = 'HOME' THEN 'HOME'
        WHEN discharge_location = 'HOSPICE' THEN 'HOSPICE'
        ELSE 'IN-HOSPITAL DEATH'
      END AS discharge_group
    FROM 
      los_data
  )

-- Calculate statistics
SELECT 
  discharge_group,
  APPROX_QUANTILES(los, 0.25)[OFFSET(1)] AS p25_los,
  APPROX_QUANTILES(los, 0.5)[OFFSET(1)] AS median_los,
  APPROX_QUANTILES(los, 0.75)[OFFSET(1)] AS p75_los,
  APPROX_QUANTILES(los, 0.9)[OFFSET(1)] AS p90_los,
  AVG(los) AS mean_los,
  COUNT(CASE WHEN los <= 14 THEN 1 END) * 100.0 / COUNT(*) AS pct_los_leq_14
FROM 
  discharge_categories
GROUP BY 
  discharge_group;