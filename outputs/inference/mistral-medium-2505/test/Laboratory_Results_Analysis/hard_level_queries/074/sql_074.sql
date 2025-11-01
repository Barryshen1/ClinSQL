WITH
-- Define heart failure ICD codes (ICD-9 and ICD-10)
heart_failure_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code IN ('428.0', '428.1', '428.20', '428.21', '428.22', '428.23', '428.30', '428.31', '428.32', '428.33', '428.40', '428.41', '428.42', '428.43', '428.9'))
    OR (icd_version = 10 AND icd_code LIKE 'I50.%')
),

-- Get heart failure patients
hf_patients AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN heart_failure_codes hf ON d.icd_code = hf.icd_code AND d.icd_version = hf.icd_version
),

-- Get general inpatients (male, 37-47, no heart failure)
general_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.subject_id NOT IN (SELECT subject_id FROM hf_patients)
),

-- Get all lab events within first 72 hours with critical flags
critical_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    d.category,
    l.flag
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
  WHERE
    l.flag IN ('abnormal', 'critically abnormal', 'critical', 'panic')
    AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
),

-- Calculate instability score (count of unique critical lab categories per admission)
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT category) AS instability_score
  FROM critical_labs
  GROUP BY subject_id, hadm_id
),

-- Combine patient groups with their scores
patient_scores AS (
  SELECT
    'Heart Failure' AS patient_group,
    s.subject_id,
    s.hadm_id,
    s.instability_score,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM instability_scores s
  JOIN hf_patients hf ON s.subject_id = hf.subject_id AND s.hadm_id = hf.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON s.hadm_id = a.hadm_id

  UNION ALL

  SELECT
    'General Inpatient' AS patient_group,
    s.subject_id,
    s.hadm_id,
    s.instability_score,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM instability_scores s
  JOIN general_patients g ON s.subject_id = g.subject_id AND s.hadm_id = g.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON s.hadm_id = a.hadm_id
),

-- Calculate critical event rates
critical_event_rates AS (
  SELECT
    patient_group,
    COUNT(DISTINCT hadm_id) AS total_admissions,
    COUNT(DISTINCT CASE WHEN instability_score > 0 THEN hadm_id END) AS admissions_with_critical_labs,
    COUNT(DISTINCT CASE WHEN instability_score > 0 THEN hadm_id END) / COUNT(DISTINCT hadm_id) AS critical_event_rate,
    AVG(instability_score) AS avg_instability_score,
    MAX(instability_score) AS max_instability_score,
    AVG(los_hours) AS avg_los_hours,
    SUM(hospital_expire_flag) / COUNT(DISTINCT hadm_id) AS mortality_rate
  FROM patient_scores
  GROUP BY patient_group
)

-- Final results
SELECT * FROM critical_event_rates
ORDER BY patient_group;