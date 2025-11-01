WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.admission_type != 'NEWBORN'
),
discharge_cat AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM cohort
),
los_metrics AS (
  SELECT 
    discharge_category,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS num_long_los,
    -- Percentile rank of a 10-day LOS within each discharge category
    PERCENT_RANK() OVER (PARTITION BY discharge_category ORDER BY 10) * 100 AS ten_day_los_percentile
  FROM discharge_cat
  GROUP BY discharge_category
)
SELECT 
  discharge_category,
  total_patients,
  ROUND((num_long_los * 100.0 / total_patients), 2) AS prop_los_ge7_pct,
  ROUND(COALESCE(ten_day_los_percentile, 0), 2) AS ten_day_los_percentile_rank
FROM (
  SELECT 
    discharge_category,
    total_patients,
    num_long_los,
    MAX(ten_day_los_percentile) OVER (PARTITION BY discharge_category) AS ten_day_los_percentile
  FROM los_metrics
)
ORDER BY 
  CASE discharge_category 
    WHEN 'Home' THEN 1 
    WHEN 'Facility' THEN 2 
    WHEN 'In-hospital death' THEN 3 
  END;