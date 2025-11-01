WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 55 AND 65
),

lab_events AS (
  SELECT 
    c.hadm_id,
    l.charttime,
    l.flag,
    -- Mark abnormal labs (non-null and not 'normal')
    CASE WHEN l.flag IS NOT NULL AND l.flag != 'normal' THEN 1 ELSE 0 END AS is_abnormal
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
),

patient_scores AS (
  SELECT 
    hadm_id,
    COUNT(flag) AS total_labs,  -- Fixed: Remove invalid alias 'l'
    COALESCE(SUM(is_abnormal), 0) AS lab_instability_score  -- Handle NULLs for no-lab patients
  FROM lab_events
  GROUP BY hadm_id
),

percentile AS (
  SELECT 
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(95)] AS p95  -- BigQuery-compatible 95th percentile
  FROM patient_scores
),

cohort_with_tier AS (
  SELECT 
    c.*,
    ps.total_labs,
    ps.lab_instability_score,
    -- Handle division by zero for critical lab rate
    COALESCE(ps.lab_instability_score / NULLIF(ps.total_labs, 0), 0) AS critical_lab_rate,
    CASE 
      WHEN ps.lab_instability_score >= (SELECT p95 FROM percentile) THEN 1 
      ELSE 0 
    END AS is_top_tier
  FROM cohort c
  LEFT JOIN patient_scores ps
    ON c.hadm_id = ps.hadm_id
),

group_metrics AS (
  SELECT 
    'Top Tier' AS group_label,
    COUNT(*) AS count_admissions,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los,
    AVG(hospital_expire_flag) * 100 AS mortality_rate,
    AVG(critical_lab_rate) AS avg_critical_lab_rate
  FROM cohort_with_tier
  WHERE is_top_tier = 1
  UNION ALL
  SELECT 
    'Entire Cohort' AS group_label,
    COUNT(*) AS count_admissions,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los,
    AVG(hospital_expire_flag) * 100 AS mortality_rate,
    AVG(critical_lab_rate) AS avg_critical_lab_rate
  FROM cohort_with_tier
)

-- Final output with 95th percentile and group metrics
SELECT 
  '95th Percentile' AS group_label,
  NULL AS count_admissions,
  NULL AS avg_los,
  NULL AS mortality_rate,
  NULL AS avg_critical_lab_rate,
  (SELECT p95 FROM percentile) AS percentile_95_value
UNION ALL
SELECT 
  group_label,
  count_admissions,
  avg_los,
  mortality_rate,
  avg_critical_lab_rate,
  NULL AS percentile_95_value
FROM group_metrics;