WITH
-- Define heart failure ICD codes
heart_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I50.%'
),

-- Get male patients aged 54-64 with heart failure
target_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  JOIN heart_failure_codes hf ON d.icd_code = hf.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
),

-- Get critical lab items (example selection)
critical_labs AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN (
    'Potassium', 'Sodium', 'Creatinine', 'Glucose', 'Hemoglobin'
  )
),

-- Calculate lab instability scores for first 48h
lab_instability AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    a.admittime,
    SUM(
      CASE
        WHEN l.valuenum < l.ref_range_lower THEN POWER(l.ref_range_lower - l.valuenum, 2)
        WHEN l.valuenum > l.ref_range_upper THEN POWER(l.valuenum - l.ref_range_upper, 2)
        ELSE 0
      END
    ) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
  JOIN target_patients p ON l.subject_id = p.subject_id
  JOIN critical_labs cl ON l.itemid = cl.itemid
  WHERE l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
  GROUP BY l.subject_id, l.hadm_id, a.admittime
),

-- Calculate 95th percentile threshold
percentile_threshold AS (
  SELECT PERCENTILE_CONT(instability_score, 0.95) OVER() AS threshold
  FROM lab_instability
  LIMIT 1
),

-- Get patients above threshold
high_risk_patients AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.instability_score,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM lab_instability l
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
  CROSS JOIN percentile_threshold p
  WHERE l.instability_score >= p.threshold
),

-- Get age-matched controls (no heart failure)
control_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND p.subject_id NOT IN (SELECT subject_id FROM target_patients)
),

-- Calculate critical lab rates for high-risk patients
high_risk_lab_rates AS (
  SELECT
    COUNT(DISTINCT l.subject_id) AS patient_count,
    COUNT(l.labevent_id) AS total_labs,
    COUNT(CASE WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1 END) AS abnormal_labs
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN high_risk_patients h ON l.subject_id = h.subject_id
  JOIN critical_labs cl ON l.itemid = cl.itemid
  WHERE l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),

-- Calculate critical lab rates for controls
control_lab_rates AS (
  SELECT
    COUNT(DISTINCT l.subject_id) AS patient_count,
    COUNT(l.labevent_id) AS total_labs,
    COUNT(CASE WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1 END) AS abnormal_labs
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN control_patients c ON l.subject_id = c.subject_id
  JOIN critical_labs cl ON l.itemid = cl.itemid
  WHERE l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
)

-- Final results
SELECT
  -- High-risk patient outcomes
  (SELECT COUNT(*) FROM high_risk_patients WHERE hospital_expire_flag = 1) AS high_risk_mortality_count,
  (SELECT COUNT(*) FROM high_risk_patients) AS high_risk_patient_count,
  (SELECT AVG(los_hours) FROM high_risk_patients) AS avg_los_hours,

  -- Lab comparison
  (SELECT abnormal_labs/NULLIF(total_labs, 0) FROM high_risk_lab_rates) AS high_risk_abnormal_rate,
  (SELECT abnormal_labs/NULLIF(total_labs, 0) FROM control_lab_rates) AS control_abnormal_rate,

  -- 95th percentile threshold
  (SELECT threshold FROM percentile_threshold) AS instability_threshold;