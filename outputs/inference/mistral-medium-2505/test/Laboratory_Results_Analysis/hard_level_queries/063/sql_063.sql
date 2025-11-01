WITH
-- Define pulmonary embolism ICD codes (ICD-10: I26.*)
pe_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I26%'
),

-- Get female patients aged 53-63 with pulmonary embolism
target_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN pe_icd_codes pe ON d.icd_code = pe.icd_code
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),

-- Get relevant lab tests within 72 hours of admission
relevant_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN target_patients t ON l.subject_id = t.subject_id AND l.hadm_id = t.hadm_id
  WHERE
    l.charttime BETWEEN t.admittime AND TIMESTAMP_ADD(t.admittime, INTERVAL 72 HOUR)
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND l.valuenum IS NOT NULL
),

-- Calculate lab instability score for each patient
lab_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(
      CASE
        WHEN valuenum < ref_range_lower THEN POWER((ref_range_lower - valuenum) / NULLIF(ref_range_lower, 0), 2)
        WHEN valuenum > ref_range_upper THEN POWER((valuenum - ref_range_upper) / NULLIF(ref_range_upper, 0), 2)
        ELSE 0
      END
    ) AS instability_score
  FROM relevant_labs
  GROUP BY subject_id, hadm_id
),

-- Calculate 75th percentile of instability scores
score_threshold AS (
  SELECT PERCENTILE_CONT(instability_score, 0.75) OVER() AS threshold
  FROM lab_scores
  LIMIT 1
),

-- Get patients with scores ≥75th percentile
high_risk_patients AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.los_days,
    t.hospital_expire_flag,
    s.instability_score
  FROM target_patients t
  JOIN lab_scores s ON t.subject_id = s.subject_id AND t.hadm_id = s.hadm_id
  CROSS JOIN score_threshold st
  WHERE s.instability_score >= st.threshold
),

-- Calculate overall inpatient metrics for comparison
general_inpatients AS (
  SELECT
    COUNT(*) AS total_patients,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS total_deaths,
    AVG(los_days) AS avg_los
  FROM target_patients
)

-- Final results
SELECT
  -- High-risk patient metrics
  COUNT(*) AS high_risk_patients,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days,

  -- Comparison to general inpatients
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) /
    (SELECT total_deaths FROM general_inpatients) * (SELECT total_patients FROM general_inpatients), 2) AS mortality_ratio,
  ROUND(AVG(los_days) / (SELECT avg_los FROM general_inpatients), 2) AS los_ratio

FROM high_risk_patients;