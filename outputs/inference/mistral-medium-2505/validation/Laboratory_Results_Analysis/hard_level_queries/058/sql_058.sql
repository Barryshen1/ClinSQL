WITH
-- Define ACS ICD codes (I20-I25 range)
acs_icd_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code BETWEEN 'I20' AND 'I25'
),

-- Get female patients aged 40-50 with ACS diagnosis
acs_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN acs_icd_codes acs ON d.icd_code = acs.icd_code
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.admittime IS NOT NULL
),

-- Define critical lab tests (example: troponin, creatinine, hemoglobin)
critical_labs AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    label LIKE '%Troponin%'
    OR label LIKE '%Creatinine%'
    OR label LIKE '%Hemoglobin%'
    OR label LIKE '%Potassium%'
    OR label LIKE '%Sodium%'
    OR label LIKE '%Glucose%'
),

-- Get first 48 hours of lab results for ACS patients
first_48h_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN acs_patients a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN critical_labs cl ON l.itemid = cl.itemid
  WHERE
    l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
),

-- Calculate lab instability score (count of all lab results as proxy for instability)
lab_instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(*) AS instability_score
  FROM first_48h_labs
  GROUP BY subject_id, hadm_id
),

-- Calculate 90th percentile threshold
percentile_threshold AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS threshold
  FROM lab_instability_scores
  LIMIT 1
),

-- Get patients at/above 90th percentile
high_risk_patients AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.instability_score,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM lab_instability_scores l
  JOIN acs_patients a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  CROSS JOIN percentile_threshold p
  WHERE l.instability_score >= p.threshold
),

-- Calculate critical lab rate for high-risk patients
high_risk_lab_rate AS (
  SELECT
    COUNT(*) AS critical_lab_count,
    COUNT(*) AS total_lab_count
  FROM first_48h_labs f
  JOIN high_risk_patients h ON f.subject_id = h.subject_id AND f.hadm_id = h.hadm_id
),

-- Calculate critical lab rate for general inpatients (comparison group)
general_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.admittime IS NOT NULL
),

general_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN general_inpatients a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN critical_labs cl ON l.itemid = cl.itemid
  WHERE
    l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
),

general_lab_rate AS (
  SELECT
    COUNT(*) AS critical_lab_count,
    COUNT(*) AS total_lab_count
  FROM general_labs
)

-- Final results
SELECT
  (SELECT threshold FROM percentile_threshold) AS percentile_90_threshold,
  COUNT(*) AS high_risk_patient_count,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(los_hours) AS mean_los_hours,
  (SELECT critical_lab_count FROM high_risk_lab_rate) AS high_risk_critical_labs,
  (SELECT total_lab_count FROM high_risk_lab_rate) AS high_risk_total_labs,
  (SELECT critical_lab_count FROM general_lab_rate) AS general_critical_labs,
  (SELECT total_lab_count FROM general_lab_rate) AS general_total_labs,
  (SELECT critical_lab_count FROM high_risk_lab_rate) /
    NULLIF((SELECT total_lab_count FROM high_risk_lab_rate), 0) AS high_risk_critical_rate,
  (SELECT critical_lab_count FROM general_lab_rate) /
    NULLIF((SELECT total_lab_count FROM general_lab_rate), 0) AS general_critical_rate
FROM high_risk_patients;