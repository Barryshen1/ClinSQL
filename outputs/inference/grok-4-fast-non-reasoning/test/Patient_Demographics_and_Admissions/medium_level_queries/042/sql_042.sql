WITH first_service AS (
  SELECT 
    subject_id,
    hadm_id,
    curr_service,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.services`
),
filtered_admissions AS (
  SELECT 
    a.*,
    p.gender,
    p.anchor_age,
    fs.curr_service,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  INNER JOIN 
    first_service fs
  ON a.hadm_id = fs.hadm_id AND fs.rn = 1
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_type = 'URGENT'
    AND fs.curr_service LIKE 'MED%'
),
grouped_stats AS (
  SELECT 
    hospital_expire_flag,
    AVG(los_days) AS mean_los,
    COUNT(*) AS n
  FROM filtered_admissions
  GROUP BY hospital_expire_flag
),
rank_calc AS (
  SELECT 
    fa.*,
    SUM(CASE WHEN fa.los_days <= 5 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) OVER (PARTITION BY fa.hospital_expire_flag) AS pct_rank_5day
  FROM filtered_admissions fa
)
SELECT 
  r.hospital_expire_flag,
  g.mean_los,
  CAST(PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY hospital_expire_flag) AS INT64) AS p50_los,
  CAST(PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY hospital_expire_flag) AS INT64) AS p75_los,
  CAST(PERCENTILE_CONT(los_days, 0.9) OVER (PARTITION BY hospital_expire_flag) AS INT64) AS p90_los,
  CAST(r.pct_rank_5day AS INT64) AS pct_rank_5day
FROM rank_calc r
INNER JOIN grouped_stats g ON r.hospital_expire_flag = g.hospital_expire_flag
GROUP BY r.hospital_expire_flag, g.mean_los, r.pct_rank_5day
ORDER BY r.hospital_expire_flag;