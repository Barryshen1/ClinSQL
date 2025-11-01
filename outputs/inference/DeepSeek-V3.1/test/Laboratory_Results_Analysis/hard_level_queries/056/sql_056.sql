WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
),

labs_abnormal AS (
  SELECT 
    l.subject_id, 
    l.hadm_id,
    l.labevent_id,
    CASE 
      WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1
      ELSE 0
    END AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort c
    ON l.hadm_id = c.hadm_id
  WHERE l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),

instability_scores AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT labevent_id) AS instability_score
  FROM labs_abnormal
  WHERE is_abnormal = 1
  GROUP BY hadm_id
),

percentile_calc AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100) AS percentiles
  FROM instability_scores
),

top_tier_threshold AS (
  SELECT percentiles[OFFSET(95)] AS p95
  FROM percentile_calc
),

cohort_with_instability AS (
  SELECT 
    c.*,
    COALESCE(i.instability_score, 0) AS instability_score
  FROM cohort c
  LEFT JOIN instability_scores i
    ON c.hadm_id = i.hadm_id
),

top_tier AS (
  SELECT 
    hadm.*,
    1 AS is_top_tier
  FROM cohort_with_instability hadm
  CROSS JOIN top_tier_threshold t
  WHERE hadm.instability_score >= t.p95
),

general_cohort AS (
  SELECT 
    hadm.*,
    0 AS is_top_tier
  FROM cohort_with_instability hadm
),

combined_cohorts AS (
  SELECT * FROM top_tier
  UNION ALL
  SELECT * FROM general_cohort
),

critical_labs AS (
  SELECT 
    l.hadm_id,
    COUNT(*) AS critical_labs_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN combined_cohorts c
    ON l.hadm_id = c.hadm_id
  WHERE l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.flag = 'panic'
  GROUP BY l.hadm_id
),

total_labs AS (
  SELECT 
    l.hadm_id,
    COUNT(*) AS total_labs_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN combined_cohorts c
    ON l.hadm_id = c.hadm_id
  WHERE l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
  GROUP BY l.hadm_id
),

cohort_with_lab_rates AS (
  SELECT 
    c.*,
    COALESCE(cl.critical_labs_count, 0) AS critical_labs_count,
    COALESCE(tl.total_labs_count, 0) AS total_labs_count
  FROM combined_cohorts c
  LEFT JOIN critical_labs cl
    ON c.hadm_id = cl.hadm_id
  LEFT JOIN total_labs tl
    ON c.hadm_id = tl.hadm_id
)

SELECT 
  CASE WHEN is_top_tier = 1 THEN 'Top Tier' ELSE 'General' END AS cohort_group,
  COUNT(*) AS num_patients,
  AVG(los_days) AS avg_los_days,
  SUM(hospital_expire_flag) AS mortality_count,
  AVG(hospital_expire_flag) AS mortality_rate,
  SUM(critical_labs_count) AS total_critical_labs,
  SUM(total_labs_count) AS total_labs,
  SAFE_DIVIDE(SUM(critical_labs_count), SUM(total_labs_count)) AS critical_lab_rate
FROM cohort_with_lab_rates
GROUP BY is_top_tier
ORDER BY is_top_tier DESC;