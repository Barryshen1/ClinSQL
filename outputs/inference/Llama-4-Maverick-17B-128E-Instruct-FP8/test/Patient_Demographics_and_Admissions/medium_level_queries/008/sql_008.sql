WITH 
-- Step 1: Filter patients based on age, gender, and admission type
filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type != 'ELECTIVE'  -- Non-elective admissions
),

-- Step 2: Calculate LOS and categorize discharge status
discharge_stats AS (
  SELECT 
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los,
    CASE
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB', 'NURSING HOME') THEN 'Facility'
      WHEN hospital_expire_flag = 1 THEN 'In-hospital Death'
      ELSE 'Other'
    END AS discharge_category
  FROM 
    filtered_admissions
),

-- Step 3: Compute required statistics for LOS by discharge category
los_statistics AS (
  SELECT 
    discharge_category,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
    SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS percentile_rank_7days
  FROM 
    discharge_stats
  WHERE 
    discharge_category IN ('Home', 'Facility', 'In-hospital Death')
  GROUP BY 
    discharge_category
)

-- Final output
SELECT 
  discharge_category,
  mean_los,
  median_los,
  p75_los,
  p90_los,
  percentile_rank_7days
FROM 
  los_statistics;