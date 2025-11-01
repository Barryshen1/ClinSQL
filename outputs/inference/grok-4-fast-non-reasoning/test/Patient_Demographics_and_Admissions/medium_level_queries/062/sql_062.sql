WITH eligible_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location LIKE '%HOME%' OR a.discharge_location LIKE '%SELF%' THEN 'Home/self'
      WHEN a.discharge_location LIKE '%SNF%' OR a.discharge_location LIKE '%REHAB%' OR a.discharge_location LIKE '%LTAC%' THEN 'SNF/rehab/LTACH'
      ELSE 'Other'
    END AS discharge_group
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND (p.dod IS NULL OR p.dod > a.dischtime)
    AND a.dischtime IS NOT NULL
),
grouped_stats AS (
  SELECT 
    discharge_group,
    COUNT(*) AS total_in_group,
    COUNT(CASE WHEN los_days >= 7 THEN 1 END) AS long_los_count,
    PERCENTILE_CONT(los_days, 0.14) OVER (PARTITION BY discharge_group) AS los_14th_percentile
  FROM eligible_admissions
  GROUP BY discharge_group
)
SELECT 
  discharge_group,
  SAFE_DIVIDE(long_los_count, total_in_group) AS proportion_los_ge7,
  los_14th_percentile AS los_14th_percentile_days
FROM grouped_stats
ORDER BY 
  CASE discharge_group
    WHEN 'Home/self' THEN 1
    WHEN 'SNF/rehab/LTACH' THEN 2
    WHEN 'In-hospital death' THEN 3
    ELSE 4
  END;