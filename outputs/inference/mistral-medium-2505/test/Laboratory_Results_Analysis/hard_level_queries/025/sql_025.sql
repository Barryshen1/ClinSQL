WITH
-- Define hemorrhagic stroke ICD codes
stroke_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE '431.%' OR icd_code LIKE 'I61.%'
),

-- Get female inpatients aged 48-58 with hemorrhagic stroke
stroke_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN stroke_codes sc ON d.icd_code = sc.icd_code
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.admission_type != 'NEWBORN'
),

-- Get critical lab events in first 72 hours
critical_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    d.category AS lab_category,
    COUNT(DISTINCT l.itemid) AS critical_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN stroke_patients sp ON l.subject_id = sp.subject_id AND l.hadm_id = sp.hadm_id
  WHERE
    l.charttime BETWEEN sp.admittime AND TIMESTAMP_ADD(sp.admittime, INTERVAL 72 HOUR)
    AND l.flag = 'critical'
  GROUP BY l.subject_id, l.hadm_id, d.category
),

-- Calculate lab instability score per patient
lab_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT lab_category) AS lab_instability_score
  FROM critical_labs
  GROUP BY subject_id, hadm_id
),

-- Calculate 90th percentile score
p90_score AS (
  SELECT PERCENTILE_CONT(lab_instability_score, 0.9) OVER() AS p90_value
  FROM lab_scores
  LIMIT 1
),

-- Get high-risk patients (≥P90)
high_risk_patients AS (
  SELECT
    sp.*,
    ls.lab_instability_score,
    CASE WHEN ls.lab_instability_score >= (SELECT p90_value FROM p90_score) THEN 1 ELSE 0 END AS is_high_risk
  FROM stroke_patients sp
  JOIN lab_scores ls ON sp.subject_id = ls.subject_id AND sp.hadm_id = ls.hadm_id
  WHERE ls.lab_instability_score >= (SELECT p90_value FROM p90_score)
),

-- Age-matched control cohort (female inpatients 48-58 without hemorrhagic stroke)
control_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.admission_type != 'NEWBORN'
    AND a.hadm_id NOT IN (SELECT hadm_id FROM stroke_patients)
),

-- Calculate critical labs for control cohort
control_critical_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    COUNT(DISTINCT l.itemid) AS critical_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN control_cohort cc ON l.subject_id = cc.subject_id AND l.hadm_id = cc.hadm_id
  WHERE
    l.charttime BETWEEN cc.admittime AND TIMESTAMP_ADD(cc.admittime, INTERVAL 72 HOUR)
    AND l.flag = 'critical'
  GROUP BY l.subject_id, l.hadm_id
),

-- Calculate metrics for high-risk patients
high_risk_metrics AS (
  SELECT
    COUNT(*) AS high_risk_count,
    SUM(CASE WHEN hospital_expire_flag = 1 OR dod IS NOT NULL THEN 1 ELSE 0 END) AS high_risk_deaths,
    AVG(los_hours) AS avg_los_high_risk,
    AVG(lab_instability_score) AS avg_critical_labs_high_risk
  FROM high_risk_patients
),

-- Calculate metrics for control cohort
control_metrics AS (
  SELECT
    COUNT(*) AS control_count,
    SUM(CASE WHEN hospital_expire_flag = 1 OR dod IS NOT NULL THEN 1 ELSE 0 END) AS control_deaths,
    AVG(los_hours) AS avg_los_control,
    AVG(critical_lab_count) AS avg_critical_labs_control
  FROM control_cohort cc
  LEFT JOIN control_critical_labs cl ON cc.subject_id = cl.subject_id AND cc.hadm_id = cl.hadm_id
)

-- Final results
SELECT
  (SELECT p90_value FROM p90_score) AS p90_lab_instability_score,
  high_risk_count,
  ROUND(100 * high_risk_deaths / high_risk_count, 2) AS high_risk_mortality_pct,
  ROUND(avg_los_high_risk / 24, 2) AS avg_los_days_high_risk,
  ROUND(avg_critical_labs_high_risk, 2) AS avg_critical_labs_high_risk,
  control_count,
  ROUND(100 * control_deaths / control_count, 2) AS control_mortality_pct,
  ROUND(avg_los_control / 24, 2) AS avg_los_days_control,
  ROUND(avg_critical_labs_control, 2) AS avg_critical_labs_control
FROM high_risk_metrics, control_metrics;