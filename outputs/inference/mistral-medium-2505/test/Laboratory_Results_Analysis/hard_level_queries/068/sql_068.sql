WITH
-- Define septic shock ICD codes
septic_shock_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('R65.21', 'R65.20', '785.52', '785.59')
),

-- Get female patients aged 89-99 with septic shock
septic_shock_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN septic_shock_icd s ON d.icd_code = s.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
),

-- Get general female inpatients aged 89-99 without septic shock
general_inpatients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND p.subject_id NOT IN (SELECT subject_id FROM septic_shock_patients)
),

-- Calculate instability score components within first 48 hours
instability_components AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Example components (adjust based on actual instability score definition)
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum ELSE NULL END) AS heart_rate,
    MAX(CASE WHEN ce.itemid = 220179 THEN ce.valuenum ELSE NULL END) AS systolic_bp,
    MAX(CASE WHEN ce.itemid = 220210 THEN ce.valuenum ELSE NULL END) AS diastolic_bp,
    MAX(CASE WHEN ce.itemid = 220277 THEN ce.valuenum ELSE NULL END) AS respiratory_rate,
    MAX(CASE WHEN le.itemid = 50885 THEN le.valuenum ELSE NULL END) AS lactate
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON a.subject_id = ce.subject_id AND a.hadm_id = ce.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
  WHERE a.subject_id IN (SELECT subject_id FROM septic_shock_patients)
    AND ce.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY a.subject_id, a.hadm_id
),

-- Calculate instability score (example calculation - adjust as needed)
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    -- Example score calculation (adjust based on actual criteria)
    (heart_rate * 0.1) + (systolic_bp * 0.05) + (diastolic_bp * 0.05) +
    (respiratory_rate * 0.1) + (lactate * 0.2) AS instability_score
  FROM instability_components
),

-- Get abnormal lab frequencies
abnormal_labs AS (
  SELECT
    'Septic Shock' AS cohort,
    COUNT(DISTINCT CASE WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN le.labevent_id END) AS abnormal_count,
    COUNT(DISTINCT le.labevent_id) AS total_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON le.subject_id = a.subject_id AND le.hadm_id = a.hadm_id
  WHERE le.subject_id IN (SELECT subject_id FROM septic_shock_patients)
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)

  UNION ALL

  SELECT
    'General Inpatients' AS cohort,
    COUNT(DISTINCT CASE WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN le.labevent_id END) AS abnormal_count,
    COUNT(DISTINCT le.labevent_id) AS total_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON le.subject_id = a.subject_id AND le.hadm_id = a.hadm_id
  WHERE le.subject_id IN (SELECT subject_id FROM general_inpatients)
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
),

-- Get cohort LOS and mortality
cohort_outcomes AS (
  SELECT
    'Septic Shock' AS cohort,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)) AS avg_los_hours,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
    COUNT(DISTINCT a.subject_id) AS patient_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.subject_id IN (SELECT subject_id FROM septic_shock_patients)

  UNION ALL

  SELECT
    'General Inpatients' AS cohort,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)) AS avg_los_hours,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
    COUNT(DISTINCT a.subject_id) AS patient_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.subject_id IN (SELECT subject_id FROM general_inpatients)
)

-- Final results
SELECT
  -- Instability score statistics
  (SELECT PERCENTILE_CONT(instability_score, 0.25) FROM instability_scores) AS instability_score_q1,
  (SELECT PERCENTILE_CONT(instability_score, 0.5) FROM instability_scores) AS instability_score_median,
  (SELECT PERCENTILE_CONT(instability_score, 0.75) FROM instability_scores) AS instability_score_q3,
  (SELECT PERCENTILE_CONT(instability_score, 0.75) - PERCENTILE_CONT(instability_score, 0.25) FROM instability_scores) AS instability_score_iqr,

  -- Abnormal lab frequencies
  (SELECT abnormal_count/total_count FROM abnormal_labs WHERE cohort = 'Septic Shock') AS septic_shock_abnormal_lab_freq,
  (SELECT abnormal_count/total_count FROM abnormal_labs WHERE cohort = 'General Inpatients') AS general_abnormal_lab_freq,

  -- Cohort outcomes
  (SELECT avg_los_hours FROM cohort_outcomes WHERE cohort = 'Septic Shock') AS septic_shock_avg_los_hours,
  (SELECT mortality_count/patient_count FROM cohort_outcomes WHERE cohort = 'Septic Shock') AS septic_shock_mortality_rate,
  (SELECT avg_los_hours FROM cohort_outcomes WHERE cohort = 'General Inpatients') AS general_avg_los_hours,
  (SELECT mortality_count/patient_count FROM cohort_outcomes WHERE cohort = 'General Inpatients') AS general_mortality_rate;