WITH cohort AS (
  -- ACS cohort: female, age 40-50, with ACS diagnosis
  SELECT 
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
    p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          -- ICD-10: ACS (unstable angina, AMI, reinfarction)
          (d.icd_version = 10 
           AND (d.icd_code = 'I20.0' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
          OR
          -- ICD-9: ACS proxy (AMI, unstable angina)
          (d.icd_version = 9 
           AND (d.icd_code LIKE '410%' OR d.icd_code = '4111'))
        )
    )
),

general_cohort AS (
  -- General: female, age 40-50, no ACS filter
  SELECT 
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),

abnormal_labs AS (
  -- Count abnormal labs (flag != '') in first 48h for ACS cohort
  SELECT 
    l.subject_id, l.hadm_id, COUNT(*) AS num_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN cohort c 
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE l.flag != ''
    AND l.charttime >= c.admittime
    AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY l.subject_id, l.hadm_id
),

stat_labs_acs AS (
  -- Patients with at least one STAT lab in first 48h for ACS cohort
  SELECT DISTINCT
    l.subject_id, l.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN cohort c 
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE l.priority = 'STAT'
    AND l.charttime >= c.admittime
    AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
),

scores AS (
  -- Instability score + critical lab flag for ACS cohort
  SELECT 
    c.*,
    COALESCE(al.num_abnormal, 0) AS instability_score,
    CASE WHEN sl.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_critical_lab
  FROM cohort c
  LEFT JOIN abnormal_labs al 
    ON c.hadm_id = al.hadm_id
  LEFT JOIN stat_labs_acs sl 
    ON c.hadm_id = sl.hadm_id
),

p90 AS (
  -- 90th percentile score
  SELECT 
    PERCENTILE_CONT(instability_score, 0.9) AS threshold
  FROM scores
),

high_metrics AS (
  -- Metrics for high-score subgroup (>= p90) in ACS cohort
  SELECT 
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_high,
    AVG(CAST(hospital_expire_flag AS NUMERIC)) AS mort_high,
    AVG(CAST(has_critical_lab AS NUMERIC)) AS crit_rate_high
  FROM scores
  CROSS JOIN p90
  WHERE instability_score >= p90.threshold
),

stat_labs_gen AS (
  -- Patients with at least one STAT lab in first 48h for general cohort
  SELECT DISTINCT
    l.subject_id, l.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN general_cohort c 
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE l.priority = 'STAT'
    AND l.charttime >= c.admittime
    AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
),

general_with_crit AS (
  -- Critical lab flag for general cohort
  SELECT 
    g.*,
    CASE WHEN sl.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_critical_lab
  FROM general_cohort g
  LEFT JOIN stat_labs_gen sl 
    ON g.hadm_id = sl.hadm_id
),

gen_metrics AS (
  -- Metrics for general cohort
  SELECT 
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_gen,
    AVG(CAST(hospital_expire_flag AS NUMERIC)) AS mort_gen,
    AVG(CAST(has_critical_lab AS NUMERIC)) AS crit_rate_gen
  FROM general_with_crit
)

-- Final output
SELECT 
  p90.threshold AS p90_instability_score,
  high_metrics.mort_high AS high_mortality,
  high_metrics.mean_los_high AS high_mean_los,
  high_metrics.crit_rate_high AS high_critical_lab_rate,
  gen_metrics.mort_gen AS gen_mortality,
  gen_metrics.mean_los_gen AS gen_mean_los,
  gen_metrics.crit_rate_gen AS gen_critical_lab_rate
FROM p90
CROSS JOIN high_metrics
CROSS JOIN gen_metrics;