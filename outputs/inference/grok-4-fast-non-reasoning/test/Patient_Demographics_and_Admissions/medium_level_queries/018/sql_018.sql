WITH filtered_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag,
    a.discharge_location,
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
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location IN ('TRANSFER FROM HOSP', 'TRANSFER FROM SNF', 'TRANSFER FROM OTHERS', 'TRANSFER FROM MCF')
    AND (p.dod IS NULL OR p.dod > a.dischtime)
    AND a.discharge_location IS NOT NULL
    AND a.discharge_location != 'UNSCOPED'
),
discharge_groups AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE', 'SELF', 'REHAB/DISTINCT PART HOSP') THEN 'Home'
      ELSE 'Facility'
    END AS discharge_group
  FROM 
    filtered_admissions
),
agg_metrics AS (
  SELECT 
    discharge_group,
    APPROX_QUANTILES(los, 4)[OFFSET(2)] AS median_los_days,
    APPROX_QUANTILES(los, 4)[OFFSET(1)] AS iqr_los_25th,
    APPROX_QUANTILES(los, 4)[OFFSET(3)] AS iqr_los_75th,
    SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) OVER() AS pct_los_le_10_days
  FROM 
    discharge_groups
  GROUP BY 
    discharge_group
)
SELECT 
  discharge_group,
  median_los_days,
  iqr_los_25th,
  iqr_los_75th,
  pct_los_le_10_days
FROM 
  agg_metrics
ORDER BY 
  CASE discharge_group
    WHEN 'Home' THEN 1
    WHEN 'Facility' THEN 2
    WHEN 'In-hospital death' THEN 3
  END
;