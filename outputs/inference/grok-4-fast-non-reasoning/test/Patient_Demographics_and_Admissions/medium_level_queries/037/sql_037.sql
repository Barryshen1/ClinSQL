WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND EXTRACT(YEAR FROM a.admittime) >= 2008  -- Exclude anchor age 0 cases
    AND a.admission_type != 'EMERGENCY'
),
los_stats AS (
  SELECT 
    hospital_expire_flag,
    CASE hospital_expire_flag 
      WHEN 0 THEN 'Discharged Alive' 
      WHEN 1 THEN 'In-Hospital Death' 
    END AS outcome_group,
    
    -- Use APPROX_QUANTILES with 100 quantiles for precise percentile extraction
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50_los,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
    APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95_los
    
  FROM cohort
  WHERE los >= 0  -- Ensure non-negative LOS
  GROUP BY hospital_expire_flag
),
percentile_ranks AS (
  SELECT 
    hospital_expire_flag,
    -- Percentile rank of 7-day LOS: % of patients with LOS < 7 days
    ROUND(SUM(CASE WHEN los < 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS p7day_rank_pct
  FROM cohort
  WHERE los >= 0
  GROUP BY hospital_expire_flag
)
SELECT 
  ls.outcome_group,
  ls.p50_los,
  ls.p75_los,
  ls.p90_los,
  ls.p95_los,
  pr.p7day_rank_pct
FROM los_stats ls
INNER JOIN percentile_ranks pr ON ls.hospital_expire_flag = pr.hospital_expire_flag
ORDER BY ls.hospital_expire_flag;