WITH
-- Define asthma exacerbation ICD codes
asthma_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('J45.901', 'J45.902', 'J45.991', 'J45.992', 'J45.998')
),

-- Get male patients aged 52-62 with asthma exacerbation
asthma_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN asthma_codes ac ON d.icd_code = ac.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),

-- Get critical lab items
critical_labs AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN (
    'Glucose', 'Potassium', 'Sodium', 'Creatinine', 'White Blood Cells',
    'Hemoglobin', 'Platelet Count', 'INR(PT)', 'PTT', 'pH'
  )
),

-- Calculate squared deviations for each lab event
lab_deviations AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    CASE
      WHEN l.valuenum < l.ref_range_lower THEN POWER((l.ref_range_lower - l.valuenum)/NULLIF(l.ref_range_lower, 0), 2)
      WHEN l.valuenum > l.ref_range_upper THEN POWER((l.valuenum - l.ref_range_upper)/NULLIF(l.ref_range_upper, 0), 2)
      ELSE 0
    END AS squared_deviation
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN asthma_patients a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE l.itemid IN (SELECT itemid FROM critical_labs)
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
),

-- Calculate total instability score per patient
lab_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(squared_deviation) AS instability_score
  FROM lab_deviations
  GROUP BY subject_id, hadm_id
),

-- Get 90th percentile score
percentile_90 AS (
  SELECT PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90_score
  FROM lab_scores
  LIMIT 1
),

-- Identify top decile patients
top_decile AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.instability_score,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours,
    COUNT(DISTINCT l.labevent_id) AS critical_lab_events
  FROM lab_scores s
  JOIN asthma_patients a ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON s.subject_id = l.subject_id AND s.hadm_id = l.hadm_id
    AND l.itemid IN (SELECT itemid FROM critical_labs)
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  CROSS JOIN percentile_90 p
  WHERE s.instability_score >= p.p90_score
  GROUP BY s.subject_id, s.hadm_id, s.instability_score, a.hospital_expire_flag, los_hours
),

-- Age-matched comparison group (males without asthma)
age_matched_comparison AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours,
    COUNT(DISTINCT l.labevent_id) AS critical_lab_events
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
    AND l.itemid IN (SELECT itemid FROM critical_labs)
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.subject_id NOT IN (SELECT subject_id FROM asthma_patients)
  GROUP BY a.subject_id, a.hadm_id, a.hospital_expire_flag, los_hours
)

-- Final results
SELECT
  'Top Decile Asthma Patients' AS group_name,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(los_hours) AS avg_length_of_stay_hours,
  AVG(critical_lab_events) AS avg_critical_lab_events
FROM top_decile

UNION ALL

SELECT
  'Age-Matched Comparison' AS group_name,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(los_hours) AS avg_length_of_stay_hours,
  AVG(critical_lab_events) AS avg_critical_lab_events
FROM age_matched_comparison;