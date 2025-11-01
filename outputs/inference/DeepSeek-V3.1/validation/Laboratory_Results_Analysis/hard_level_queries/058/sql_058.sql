WITH acs_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 10 AND icd_code LIKE 'I21%') OR
    (icd_version = 10 AND icd_code = 'I20.0')
),

acs_cohort_base AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  INNER JOIN acs_codes ac
    ON di.icd_code = ac.icd_code AND di.icd_version = ac.icd_version
  WHERE p.gender = 'F'
),

acs_cohort AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    age_admit
  FROM acs_cohort_base
  WHERE age_admit BETWEEN 40 AND 50
),

-- Get labs for ACS cohort in first 48 hours
acs_labs AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.flag,
    -- Mark abnormal: any non-null and not 'normal'
    CASE WHEN l.flag IS NOT NULL AND l.flag != 'normal' THEN 1 ELSE 0 END AS is_abnormal,
    CASE WHEN l.flag = 'critical' THEN 1 ELSE 0 END AS is_critical
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN acs_cohort ac
    ON l.subject_id = ac.subject_id AND l.hadm_id = ac.hadm_id
  WHERE l.charttime BETWEEN ac.admittime AND DATETIME_ADD(ac.admittime, INTERVAL 48 HOUR)
),

-- Compute instability score per patient: count of distinct abnormal labs
acs_instability AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT CASE WHEN is_abnormal = 1 THEN itemid END) AS instability_score,
    SUM(is_critical) AS num_critical_labs,
    COUNT(*) AS total_labs
  FROM acs_labs
  GROUP BY subject_id, hadm_id
),

-- Compute 90th percentile of instability score for ACS cohort
percentile AS (
  SELECT 
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90_score
  FROM acs_instability
  LIMIT 1
),

-- ACS patients above threshold
acs_above_threshold AS (
  SELECT 
    ai.subject_id,
    ai.hadm_id,
    ac.admittime,
    ac.dischtime,
    ac.hospital_expire_flag,
    ai.instability_score,
    ai.num_critical_labs,
    ai.total_labs,
    -- Critical lab rate for this patient
    SAFE_DIVIDE(ai.num_critical_labs, ai.total_labs) AS critical_lab_rate
  FROM acs_instability ai
  INNER JOIN acs_cohort ac
    ON ai.subject_id = ac.subject_id AND ai.hadm_id = ac.hadm_id
  CROSS JOIN percentile p
  WHERE ai.instability_score >= p.p90_score
),

-- Metrics for ACS above threshold
acs_metrics AS (
  SELECT 
    'ACS Above Threshold' AS cohort,
    COUNT(*) AS n_patients,
    AVG(ac.hospital_expire_flag) AS mortality_rate,
    AVG(DATETIME_DIFF(ac.dischtime, ac.admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(ac.critical_lab_rate) AS mean_critical_lab_rate
  FROM acs_above_threshold ac
),

-- General cohort: female, 40-50, no ACS
general_cohort_base AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN acs_codes ac
        ON di.icd_code = ac.icd_code AND di.icd_version = ac.icd_version
      WHERE di.subject_id = p.subject_id AND di.hadm_id = a.hadm_id
    )
),

general_cohort AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    age_admit
  FROM general_cohort_base
  WHERE age_admit BETWEEN 40 AND 50
),

-- Get labs for general cohort in first 48 hours
general_labs AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.flag,
    CASE WHEN l.flag IS NOT NULL AND l.flag != 'normal' THEN 1 ELSE 0 END AS is_abnormal,
    CASE WHEN l.flag = 'critical' THEN 1 ELSE 0 END AS is_critical
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN general_cohort gc
    ON l.subject_id = gc.subject_id AND l.hadm_id = gc.hadm_id
  WHERE l.charttime BETWEEN gc.admittime AND DATETIME_ADD(gc.admittime, INTERVAL 48 HOUR)
),

-- Aggregate labs for general cohort
general_agg AS (
  SELECT 
    subject_id,
    hadm_id,
    SUM(is_critical) AS num_critical_labs,
    COUNT(*) AS total_labs,
    SAFE_DIVIDE(SUM(is_critical), COUNT(*)) AS critical_lab_rate
  FROM general_labs
  GROUP BY subject_id, hadm_id
),

-- Metrics for general cohort
general_metrics AS (
  SELECT 
    'General Inpatients' AS cohort,
    COUNT(*) AS n_patients,
    AVG(gc.hospital_expire_flag) AS mortality_rate,
    AVG(DATETIME_DIFF(gc.dischtime, gc.admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(ga.critical_lab_rate) AS mean_critical_lab_rate
  FROM general_cohort gc
  LEFT JOIN general_agg ga
    ON gc.subject_id = ga.subject_id AND gc.hadm_id = ga.hadm_id
)

-- Combine results
SELECT * FROM acs_metrics
UNION ALL
SELECT * FROM general_metrics;