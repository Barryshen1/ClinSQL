WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.hadm_id IS NOT NULL
    AND a.dischtime IS NOT NULL
),
stats AS (
  SELECT 
    CASE 
      WHEN hospital_expire_flag = 0 THEN 'Discharged Alive' 
      ELSE 'In-hospital Death' 
    END AS outcome,
    hospital_expire_flag,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90
  FROM 
    cohort
  GROUP BY 
    hospital_expire_flag, outcome
),
overall_pct AS (
  SELECT 
    (COUNTIF(los_days <= 5) * 100.0 / COUNT(*)) AS percentile_rank_5day
  FROM 
    cohort
)
SELECT 
  s.outcome,
  s.hospital_expire_flag,
  s.mean_los,
  s.p50,
  s.p75,
  s.p90,
  o.percentile_rank_5day
FROM 
  stats s
CROSS JOIN 
  overall_pct o
ORDER BY 
  s.hospital_expire_flag;