WITH
-- Define acute pancreatitis ICD codes
acute_pancreatitis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'K85.%' OR icd_code = '577.0'
),

-- Get female patients 65-75 with acute pancreatitis
pancreatitis_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN acute_pancreatitis_codes ap ON d.icd_code = ap.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Get age-matched controls (female 65-75 without acute pancreatitis)
control_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.hadm_id NOT IN (SELECT hadm_id FROM pancreatitis_patients)
),

-- Get critical lab values in first 48 hours
critical_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    MAX(CASE WHEN d.label = 'Lactate' AND l.valuenum > 4 THEN 1 ELSE 0 END) AS high_lactate,
    MAX(CASE WHEN d.label = 'White Blood Cells' AND l.valuenum > 20 THEN 1 ELSE 0 END) AS high_wbc,
    MAX(CASE WHEN d.label = 'Creatinine' AND l.valuenum > 2 THEN 1 ELSE 0 END) AS high_creatinine,
    MAX(CASE WHEN d.label = 'Glucose' AND l.valuenum > 200 THEN 1 ELSE 0 END) AS high_glucose
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN pancreatitis_patients p ON l.subject_id = p.subject_id AND l.hadm_id = p.hadm_id
  WHERE l.charttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 48 HOUR)
  GROUP BY l.subject_id, l.hadm_id
),

-- Calculate instability score (simple sum of critical lab flags)
instability_scores AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    (cl.high_lactate + cl.high_wbc + cl.high_creatinine + cl.high_glucose) AS instability_score
  FROM pancreatitis_patients p
  LEFT JOIN critical_labs cl ON p.subject_id = cl.subject_id AND p.hadm_id = cl.hadm_id
),

-- Assign quintiles based on instability score
quintiles AS (
  SELECT
    subject_id,
    hadm_id,
    instability_score,
    NTILE(5) OVER (ORDER BY instability_score) AS quintile
  FROM instability_scores
),

-- Get control group critical labs
control_critical_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    MAX(CASE WHEN d.label = 'Lactate' AND l.valuenum > 4 THEN 1 ELSE 0 END) AS high_lactate,
    MAX(CASE WHEN d.label = 'White Blood Cells' AND l.valuenum > 20 THEN 1 ELSE 0 END) AS high_wbc,
    MAX(CASE WHEN d.label = 'Creatinine' AND l.valuenum > 2 THEN 1 ELSE 0 END) AS high_creatinine,
    MAX(CASE WHEN d.label = 'Glucose' AND l.valuenum > 200 THEN 1 ELSE 0 END) AS high_glucose
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN control_patients c ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY l.subject_id, l.hadm_id
),

-- Calculate control group instability score
control_instability_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    (cl.high_lactate + cl.high_wbc + cl.high_creatinine + cl.high_glucose) AS instability_score
  FROM control_patients c
  LEFT JOIN control_critical_labs cl ON c.subject_id = cl.subject_id AND c.hadm_id = cl.hadm_id
)

-- Final results
SELECT
  'Pancreatitis' AS cohort,
  q.quintile,
  COUNT(*) AS patient_count,
  AVG(q.instability_score) AS mean_instability_score,
  AVG(p.los_hours/24) AS mean_los_days,
  AVG(CASE WHEN p.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  AVG(CASE WHEN cl.high_lactate = 1 OR cl.high_wbc = 1 OR cl.high_creatinine = 1 OR cl.high_glucose = 1 THEN 1 ELSE 0 END) AS critical_lab_percentage
FROM quintiles q
JOIN pancreatitis_patients p ON q.subject_id = p.subject_id AND q.hadm_id = p.hadm_id
LEFT JOIN critical_labs cl ON q.subject_id = cl.subject_id AND q.hadm_id = cl.hadm_id
GROUP BY q.quintile

UNION ALL

SELECT
  'Control' AS cohort,
  NULL AS quintile,
  COUNT(*) AS patient_count,
  AVG(c.instability_score) AS mean_instability_score,
  AVG(p.los_hours/24) AS mean_los_days,
  AVG(CASE WHEN p.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  AVG(CASE WHEN cl.high_lactate = 1 OR cl.high_wbc = 1 OR cl.high_creatinine = 1 OR cl.high_glucose = 1 THEN 1 ELSE 0 END) AS critical_lab_percentage
FROM control_instability_scores c
JOIN control_patients p ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
LEFT JOIN control_critical_labs cl ON c.subject_id = cl.subject_id AND c.hadm_id = cl.hadm_id
GROUP BY cohort
ORDER BY cohort, quintile;