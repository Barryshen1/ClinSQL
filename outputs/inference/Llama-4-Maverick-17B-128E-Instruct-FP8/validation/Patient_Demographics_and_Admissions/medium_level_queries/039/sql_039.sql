WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_type IN ('EMERGENCY', 'URGENT')
),
discharge_outcomes AS (
  SELECT 
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_outcome
  FROM 
    filtered_admissions
)
SELECT 
  discharge_outcome,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS percentile_75,
  SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile_rank_7day
FROM 
  discharge_outcomes
GROUP BY 
  discharge_outcome
ORDER BY 
  discharge_outcome;