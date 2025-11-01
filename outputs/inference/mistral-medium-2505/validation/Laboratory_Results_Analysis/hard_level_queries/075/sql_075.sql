WITH
-- Define age range and gender
male_patients_42_52 AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 42 AND 52
),

-- Identify patients with DVT
dvt_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    male_patients_42_52 p ON d.subject_id = p.subject_id
  WHERE
    -- ICD-9 codes for DVT (453.4x)
    (d.icd_version = 9 AND d.icd_code LIKE '453.4%')
    OR
    -- ICD-10 codes for DVT (I82.x)
    (d.icd_version = 10 AND d.icd_code LIKE 'I82.%')
),

-- Get admission times for DVT patients
dvt_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    dvt_patients d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
),

-- Get lab events within 72 hours of admission
dvt_lab_events AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.valueuom,
    d.label,
    l.ref_range_lower,
    l.ref_range_upper
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN
    dvt_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE
    l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),

-- Calculate lab instability score (count of abnormal labs)
lab_instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(CASE WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1 END) AS instability_score
  FROM
    dvt_lab_events
  GROUP BY
    subject_id, hadm_id
),

-- Calculate 95th percentile of instability scores
percentile_95 AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.95) AS p95
  FROM
    lab_instability_scores
),

-- Get high-risk patients (≥95th percentile)
high_risk_patients AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.instability_score,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    lab_instability_scores l
  JOIN
    dvt_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  CROSS JOIN
    percentile_95 p
  WHERE
    l.instability_score >= p.p95
),

-- Calculate critical lab rates for high-risk patients
high_risk_lab_rates AS (
  SELECT
    COUNT(CASE WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1 END) AS critical_labs,
    COUNT(*) AS total_labs
  FROM
    dvt_lab_events l
  JOIN
    high_risk_patients h ON l.subject_id = h.subject_id AND l.hadm_id = h.hadm_id
),

-- Calculate critical lab rates for all inpatients (for comparison)
all_inpatients_lab_rates AS (
  SELECT
    COUNT(CASE WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1 END) AS critical_labs,
    COUNT(*) AS total_labs
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
)

-- Final results
SELECT
  -- 95th percentile of instability score
  p.p95 AS percentile_95_instability_score,

  -- High-risk patient outcomes
  COUNT(DISTINCT h.subject_id) AS high_risk_patient_count,
  SUM(CASE WHEN h.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS high_risk_mortality_count,
  AVG(h.los_days) AS high_risk_avg_los_days,

  -- Critical lab rates comparison
  hr.critical_labs AS high_risk_critical_labs,
  hr.total_labs AS high_risk_total_labs,
  ai.critical_labs AS all_inpatients_critical_labs,
  ai.total_labs AS all_inpatients_total_labs,
  (hr.critical_labs / hr.total_labs) AS high_risk_critical_rate,
  (ai.critical_labs / ai.total_labs) AS all_inpatients_critical_rate
FROM
  percentile_95 p,
  high_risk_patients h,
  high_risk_lab_rates hr,
  all_inpatients_lab_rates ai;