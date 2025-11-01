WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate LOS in fractional days
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code LIKE '4151%') 
        OR (icd_version = 10 AND icd_code LIKE 'I26%')
    )
),
-- Filter for age 53-63
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_at_admission BETWEEN 53 AND 63
),
-- Count critical labs in first 72 hours
critical_labs_72h AS (
  SELECT 
    fc.hadm_id,
    COUNT(le.labevent_id) AS critical_count_72h
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fc.hadm_id = le.hadm_id
    AND fc.subject_id = le.subject_id
    AND le.charttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 72 HOUR)
    AND le.flag = 'critical'
  GROUP BY fc.hadm_id
),
-- Count critical labs for entire stay
total_critical_labs AS (
  SELECT 
    fc.hadm_id,
    COUNT(le.labevent_id) AS total_critical_count
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fc.hadm_id = le.hadm_id
    AND fc.subject_id = le.subject_id
    AND le.flag = 'critical'
  GROUP BY fc.hadm_id
),
-- Combine counts and LOS
cohort_with_counts AS (
  SELECT 
    fc.*,
    COALESCE(cl72.critical_count_72h, 0) AS critical_count_72h,
    COALESCE(tcl.total_critical_count, 0) AS total_critical_count
  FROM filtered_cohort fc
  LEFT JOIN critical_labs_72h cl72 ON fc.hadm_id = cl72.hadm_id
  LEFT JOIN total_critical_labs tcl ON fc.hadm_id = tcl.hadm_id
),
-- Compute 75th percentile of 72h critical count
p75 AS (
  SELECT 
    APPROX_QUANTILES(critical_count_72h, 100)[OFFSET(75)] AS p75_value
  FROM cohort_with_counts
),
-- High-score group (≥75th percentile)
high_score_group AS (
  SELECT 
    cwc.*
  FROM cohort_with_counts cwc
  CROSS JOIN p75
  WHERE cwc.critical_count_72h >= p75.p75_value
),
-- Aggregate stats for high-score group
high_score_stats AS (
  SELECT 
    COUNT(*) AS n_high_score,
    AVG(hospital_expire_flag) * 100 AS mortality_rate,
    AVG(los_days) AS mean_los_days,
    COALESCE(SUM(total_critical_count) / NULLIF(SUM(los_days), 0), 0) AS critical_lab_rate_high
  FROM high_score_group
),
-- Critical-lab rate for entire cohort
cohort_critical_rate AS (
  SELECT 
    COALESCE(SUM(total_critical_count) / NULLIF(SUM(los_days), 0), 0) AS critical_lab_rate_cohort
  FROM cohort_with_counts
)
-- Final output
SELECT 
  (SELECT p75_value FROM p75) AS instability_score_75th_percentile,
  hsg.mortality_rate,
  hsg.mean_los_days,
  hsg.critical_lab_rate_high,
  cc.critical_lab_rate_cohort
FROM high_score_stats hsg, cohort_critical_rate cc;