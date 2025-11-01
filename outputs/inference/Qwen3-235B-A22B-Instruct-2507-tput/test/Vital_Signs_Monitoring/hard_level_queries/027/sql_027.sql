WITH rrt_procedures AS (
  SELECT DISTINCT pe.stay_id, pe.subject_id, pe.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE LOWER(di.category) LIKE '%renal replacement%'
     OR LOWER(di.label) LIKE '%dialysis%'
     OR LOWER(di.label) LIKE '%crrt%'
),
patient_ages AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM ist.intime) - p.anchor_year) AS age_at_icu_admission,
    ist.stay_id,
    ist.hadm_id,
    ist.intime,
    ist.outtime,
    ist.los AS icu_los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ist ON p.subject_id = ist.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ist.hadm_id = a.hadm_id
  JOIN rrt_procedures rrt ON ist.stay_id = rrt.stay_id
),
cohort AS (
  SELECT *
  FROM patient_ages
  WHERE gender = 'F'
    AND age_at_icu_admission BETWEEN 58 AND 68
),
all_rrt AS (
  SELECT *
  FROM patient_ages
),
-- Get relevant vital signs: HR and MAP
vitals AS (
  SELECT 
    ce.subject_id,
    ce.stay_id,
    ce.charttime,
    MAX(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum END) AS heart_rate,
    MAX(CASE WHEN di.label IN ('Mean Blood Pressure', 'Mean BP') THEN ce.valuenum END) AS mean_ap
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label IN ('Heart Rate', 'Mean Blood Pressure', 'Mean BP')
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.subject_id, ce.stay_id, ce.charttime
),
vitals_72h AS (
  SELECT 
    v.*,
    DATETIME_TRUNC(v.charttime, HOUR) AS chart_hour
  FROM vitals v
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ist ON v.stay_id = ist.stay_id
  WHERE v.charttime >= ist.intime
    AND v.charttime <= ist.intime + INTERVAL '72' HOUR
),
hourly_summary AS (
  SELECT 
    stay_id,
    chart_hour,
    LOGICAL_OR(heart_rate > 100) AS has_tachycardia,
    LOGICAL_OR(mean_ap < 65) AS has_hypotension
  FROM vitals_72h
  GROUP BY stay_id, chart_hour
),
patient_metrics AS (
  SELECT 
    pa.stay_id,
    pa.subject_id,
    pa.hadm_id,
    pa.age_at_icu_admission,
    pa.gender,
    pa.icu_los,
    pa.hospital_expire_flag,
    -- Total hours with tachycardia
    COALESCE(SUM(CASE WHEN hs.has_tachycardia THEN 1 ELSE 0 END), 0) AS tachycardia_hours,
    -- Total hours with hypotension
    COALESCE(SUM(CASE WHEN hs.has_hypotension THEN 1 ELSE 0 END), 0) AS hypotension_hours,
    -- Total hours with both (vital instability)
    COALESCE(SUM(CASE WHEN hs.has_tachycardia AND hs.has_hypotension THEN 1 ELSE 0 END), 0) AS unstable_hours,
    -- Total observation hours (up to 72)
    COALESCE(COUNT(DISTINCT hs.chart_hour), 0) AS observed_hours
  FROM all_rrt pa
  LEFT JOIN hourly_summary hs ON pa.stay_id = hs.stay_id
  GROUP BY pa.stay_id, pa.subject_id, pa.hadm_id, pa.age_at_icu_admission, pa.gender, pa.icu_los, pa.hospital_expire_flag
),
-- Compute vital instability index: fraction of observed hours with concurrent instability
indexed_metrics AS (
  SELECT 
    *,
    CASE 
      WHEN observed_hours > 0 THEN unstable_hours / observed_hours 
      ELSE 0 
    END AS vital_instability_index
  FROM patient_metrics
),
-- Target group: women 58-68 on RRT
target_group AS (
  SELECT *
  FROM indexed_metrics
  WHERE gender = 'F' AND age_at_icu_admission BETWEEN 58 AND 68
),
-- Other RRT patients (for comparison)
other_group AS (
  SELECT *
  FROM indexed_metrics
  WHERE NOT (gender = 'F' AND age_at_icu_admission BETWEEN 58 AND 68)
),
-- Percentiles for target group
percentiles_target AS (
  SELECT
    APPROX_QUANTILES(vital_instability_index, 1000)[OFFSET(250)] AS p25,
    APPROX_QUANTILES(vital_instability_index, 1000)[OFFSET(500)] AS p50,
    APPROX_QUANTILES(vital_instability_index, 1000)[OFFSET(750)] AS p75,
    APPROX_QUANTILES(vital_instability_index, 1000)[OFFSET(900)] AS p90
  FROM target_group
),
iqr_target AS (
  SELECT 
    p25, p50, p75, p90,
    (p75 - p25) AS iqr
  FROM percentiles_target
),
-- Summary statistics for comparison
comparison_stats AS (
  SELECT
    'target' AS group_type,
    AVG(tachycardia_hours) AS avg_tachycardia_hours,
    AVG(hypotension_hours) AS avg_hypotension_hours,
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM target_group
  UNION ALL
  SELECT
    'other' AS group_type,
    AVG(tachycardia_hours) AS avg_tachycardia_hours,
    AVG(hypotension_hours) AS avg_hypotension_hours,
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM other_group
)
-- Final output
SELECT
  i.*,
  (SELECT * EXCEPT(group_type) FROM comparison_stats WHERE group_type = 'target') AS target_stats,
  (SELECT * EXCEPT(group_type) FROM comparison_stats WHERE group_type = 'other') AS other_stats
FROM iqr_target i;