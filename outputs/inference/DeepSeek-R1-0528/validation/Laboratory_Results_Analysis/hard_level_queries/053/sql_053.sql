with all 6 labs in first 72h
WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
    -- Ensure all 6 labs exist within 72h
    AND EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` WHERE subject_id = a.subject_id AND hadm_id = a.hadm_id AND itemid = 50912 AND charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR))
    AND EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` WHERE subject_id = a.subject_id AND hadm_id = a.hadm_id AND itemid = 50922 AND charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR))
    AND EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` WHERE subject_id = a.subject_id AND hadm_id = a.hadm_id AND itemid = 51265 AND charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR))
    AND EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` WHERE subject_id = a.subject_id AND hadm_id = a.hadm_id AND itemid = 51222 AND charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR))
    AND EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` WHERE subject_id = a.subject_id AND hadm_id = a.hadm_id AND itemid = 52610 AND charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR))
    AND EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` WHERE subject_id = a.subject_id AND hadm_id = a.hadm_id AND itemid = 51301 AND charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR))
),

-- Calculate min/max values and ref ranges for each lab within 72h
labs_72h AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    le.itemid,
    MIN(le.valuenum) AS min_val,
    MAX(le.valuenum) AS max_val,
    dl.ref_range_upper - dl.ref_range_lower AS ref_width
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id 
    AND c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE le.itemid IN (50912, 50922, 51265, 51222, 52610, 51301)  -- 6 required labs
  GROUP BY c.subject_id, c.hadm_id, le.itemid, dl.ref_range_upper, dl.ref_range_lower
),

-- Compute instability score per patient (sum of normalized ranges)
instability_scores AS (
  SELECT 
    subject_id, 
    hadm_id,
    SUM((max_val - min_val) / ref_width) AS instability_score
  FROM labs_72h
  GROUP BY subject_id, hadm_id
),

-- Get 90th percentile of instability score
percentile_90 AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM instability_scores
),

-- Identify top-tier patients (instability score >= 90th percentile)
top_tier AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.instability_score
  FROM instability_scores i
  CROSS JOIN percentile_90 p
  WHERE i.instability_score >= p.p90_score
),

-- Critical flags for all cohort patients (entire hospital stay)
critical_flags AS (
  SELECT 
    le.subject_id, 
    le.hadm_id,
    le.itemid,
    MAX(CASE WHEN le.flag = 'critical' THEN 1 ELSE 0 END) AS is_critical  -- 1 if any critical value
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id 
    AND c.hadm_id = le.hadm_id
  WHERE le.itemid IN (50912, 50922, 51265, 51222, 52610, 51301)
  GROUP BY le.subject_id, le.hadm_id, le.itemid
),

-- Calculate metrics: mortality, LOS, and critical rates
cohort_metrics AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.hospital_expire_flag,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    -- Mark top-tier patients
    CASE WHEN t.subject_id IS NOT NULL THEN 1 ELSE 0 END AS is_top_tier
  FROM cohort c
  LEFT JOIN top_tier t
    ON c.subject_id = t.subject_id AND c.hadm_id = t.hadm_id
),

-- Aggregate results for final output
mortality_los_summary AS (
  SELECT 
    'Top-tier' AS cohort_group,
    COUNT(*) AS num_patients,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(los_days) AS avg_los_days
  FROM cohort_metrics
  WHERE is_top_tier = 1
  GROUP BY cohort_group
),

critical_rates AS (
  SELECT 
    dl.itemid,
    dl.label,
    -- Top-tier critical rate
    SAFE_DIVIDE(SUM(CASE WHEN m.is_top_tier = 1 AND cf.is_critical = 1 THEN 1 ELSE 0 END), COUNT(DISTINCT CASE WHEN m.is_top_tier = 1 THEN m.subject_id END)) AS top_tier_critical_rate,
    -- Overall cohort critical rate
    SAFE_DIVIDE(SUM(cf.is_critical), COUNT(DISTINCT m.subject_id)) AS all_critical_rate
  FROM cohort_metrics m
  LEFT JOIN critical_flags cf
    ON m.subject_id = cf.subject_id AND m.hadm_id = cf.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON cf.itemid = dl.itemid
  GROUP BY dl.itemid, dl.label
)

-- Final output: 90th percentile, top-tier metrics, and critical rates
SELECT 
  (SELECT p90_score FROM percentile_90) AS instability_score_90th_percentile,
  ml.*,
  cr.*
FROM mortality_los_summary ml
CROSS JOIN critical_rates cr;