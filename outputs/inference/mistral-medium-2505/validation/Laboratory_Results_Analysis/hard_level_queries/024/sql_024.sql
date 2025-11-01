WITH
-- Define cardiac arrest ICD codes (I46.x)
cardiac_arrest_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I46%'
),

-- Get female patients aged 53-63 with cardiac arrest
target_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN cardiac_arrest_codes c ON d.icd_code = c.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),

-- Get critical lab items (example: lactate, troponin, creatinine)
critical_labs AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN ('Lactate', 'Troponin I', 'Creatinine')
),

-- Calculate lab instability score (count of abnormal labs within 48h of admission)
lab_scores AS (
  SELECT
    t.hadm_id,
    COUNT(CASE
      WHEN (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
      THEN 1
      ELSE NULL
    END) AS instability_score
  FROM target_patients t
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON t.hadm_id = l.hadm_id
  JOIN critical_labs cl ON l.itemid = cl.itemid
  WHERE l.charttime BETWEEN t.admittime AND TIMESTAMP_ADD(t.admittime, INTERVAL 48 HOUR)
  GROUP BY t.hadm_id
),

-- Calculate 90th percentile of instability scores
percentile_90 AS (
  SELECT PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90
  FROM lab_scores
  LIMIT 1
),

-- Get patients with scores >= 90th percentile
high_risk_patients AS (
  SELECT
    s.hadm_id,
    s.instability_score,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours,
    a.admittime
  FROM lab_scores s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON s.hadm_id = a.hadm_id
  CROSS JOIN percentile_90 p
  WHERE s.instability_score >= p.p90
),

-- Calculate critical lab frequency for high-risk vs all inpatients
lab_frequency AS (
  SELECT
    'High Risk' AS cohort,
    COUNT(DISTINCT l.hadm_id) AS patient_count,
    COUNT(l.labevent_id) AS total_labs,
    COUNT(DISTINCT CASE WHEN l.itemid IN (SELECT itemid FROM critical_labs) THEN l.hadm_id END) AS critical_lab_patients
  FROM high_risk_patients h
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON h.hadm_id = l.hadm_id
  WHERE l.charttime BETWEEN h.admittime AND TIMESTAMP_ADD(h.admittime, INTERVAL 48 HOUR)

  UNION ALL

  SELECT
    'All Inpatients' AS cohort,
    COUNT(DISTINCT l.hadm_id) AS patient_count,
    COUNT(l.labevent_id) AS total_labs,
    COUNT(DISTINCT CASE WHEN l.itemid IN (SELECT itemid FROM critical_labs) THEN l.hadm_id END) AS critical_lab_patients
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN cardiac_arrest_codes c ON d.icd_code = c.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
)

-- Final results
SELECT
  (SELECT p90 FROM percentile_90) AS percentile_90_score,
  COUNT(DISTINCT hadm_id) AS high_risk_patient_count,
  SUM(hospital_expire_flag) AS mortality_count,
  AVG(los_hours) AS mean_los_hours,
  (SELECT COUNT(DISTINCT hadm_id) FROM lab_scores) AS total_patient_count,
  (SELECT patient_count FROM lab_frequency WHERE cohort = 'High Risk') AS high_risk_lab_patients,
  (SELECT patient_count FROM lab_frequency WHERE cohort = 'All Inpatients') AS all_inpatient_lab_patients,
  (SELECT total_labs FROM lab_frequency WHERE cohort = 'High Risk') AS high_risk_total_labs,
  (SELECT total_labs FROM lab_frequency WHERE cohort = 'All Inpatients') AS all_inpatient_total_labs,
  (SELECT critical_lab_patients FROM lab_frequency WHERE cohort = 'High Risk') AS high_risk_critical_lab_patients,
  (SELECT critical_lab_patients FROM lab_frequency WHERE cohort = 'All Inpatients') AS all_inpatient_critical_lab_patients
FROM high_risk_patients;