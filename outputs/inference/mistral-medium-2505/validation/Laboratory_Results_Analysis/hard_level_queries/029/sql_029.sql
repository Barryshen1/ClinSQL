WITH
-- Define HHS ICD codes (ICD-9: 250.2x, ICD-10: E11.0x)
hhs_icd_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE '250.2%' OR icd_code LIKE 'E11.0%'
),

-- Get female patients aged 50-60
female_patients_50_60 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 50 AND 60
),

-- Get admissions with HHS diagnosis
hhs_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_patients_50_60 p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN hhs_icd_codes h ON d.icd_code = h.icd_code AND d.icd_version = h.icd_version
),

-- Calculate laboratory instability score for first 48 hours
lab_instability_scores AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    -- Example score calculation (adjust based on actual clinical definition)
    SUM(CASE
          WHEN li.category = 'Glucose' AND l.valuenum > 300 THEN 1
          WHEN li.category = 'Sodium' AND l.valuenum > 145 THEN 1
          WHEN li.category = 'Potassium' AND (l.valuenum < 3.5 OR l.valuenum > 5.0) THEN 1
          WHEN li.category = 'Creatinine' AND l.valuenum > 1.2 THEN 1
          ELSE 0
        END) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  JOIN hhs_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY l.subject_id, l.hadm_id
),

-- Calculate 75th percentile of lab instability scores
score_threshold AS (
  SELECT PERCENTILE_CONT(lab_instability_score, 0.75) OVER() AS threshold
  FROM lab_instability_scores
  LIMIT 1
),

-- Get admissions with score >= 75th percentile
high_risk_admissions AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.lab_instability_score,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM lab_instability_scores s
  JOIN hhs_admissions a ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
  CROSS JOIN score_threshold t
  WHERE s.lab_instability_score >= t.threshold
),

-- Compare critical lab rates with general inpatients
general_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.hadm_id NOT IN (SELECT hadm_id FROM hhs_admissions)
),

-- Calculate critical lab rates for high-risk admissions
high_risk_lab_rates AS (
  SELECT
    COALESCE(COUNT(DISTINCT CASE WHEN li.category = 'Glucose' AND l.valuenum > 300 THEN l.hadm_id END) / NULLIF(COUNT(DISTINCT l.hadm_id), 0), 0) AS high_glucose_rate,
    COALESCE(COUNT(DISTINCT CASE WHEN li.category = 'Sodium' AND l.valuenum > 145 THEN l.hadm_id END) / NULLIF(COUNT(DISTINCT l.hadm_id), 0), 0) AS high_sodium_rate,
    COALESCE(COUNT(DISTINCT CASE WHEN li.category = 'Potassium' AND (l.valuenum < 3.5 OR l.valuenum > 5.0) THEN l.hadm_id END) / NULLIF(COUNT(DISTINCT l.hadm_id), 0), 0) AS abnormal_potassium_rate,
    COALESCE(COUNT(DISTINCT CASE WHEN li.category = 'Creatinine' AND l.valuenum > 1.2 THEN l.hadm_id END) / NULLIF(COUNT(DISTINCT l.hadm_id), 0), 0) AS high_creatinine_rate
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  JOIN high_risk_admissions h ON l.subject_id = h.subject_id AND l.hadm_id = h.hadm_id
),

-- Calculate critical lab rates for general inpatients
general_lab_rates AS (
  SELECT
    COALESCE(COUNT(DISTINCT CASE WHEN li.category = 'Glucose' AND l.valuenum > 300 THEN l.hadm_id END) / NULLIF(COUNT(DISTINCT l.hadm_id), 0), 0) AS high_glucose_rate,
    COALESCE(COUNT(DISTINCT CASE WHEN li.category = 'Sodium' AND l.valuenum > 145 THEN l.hadm_id END) / NULLIF(COUNT(DISTINCT l.hadm_id), 0), 0) AS high_sodium_rate,
    COALESCE(COUNT(DISTINCT CASE WHEN li.category = 'Potassium' AND (l.valuenum < 3.5 OR l.valuenum > 5.0) THEN l.hadm_id END) / NULLIF(COUNT(DISTINCT l.hadm_id), 0), 0) AS abnormal_potassium_rate,
    COALESCE(COUNT(DISTINCT CASE WHEN li.category = 'Creatinine' AND l.valuenum > 1.2 THEN l.hadm_id END) / NULLIF(COUNT(DISTINCT l.hadm_id), 0), 0) AS high_creatinine_rate
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  JOIN general_inpatients g ON l.subject_id = g.subject_id AND l.hadm_id = g.hadm_id
)

-- Final results
SELECT
  -- 75th percentile threshold
  (SELECT threshold FROM score_threshold) AS lab_instability_score_75th_percentile,

  -- High-risk admissions metrics
  COUNT(DISTINCT h.hadm_id) AS high_risk_admission_count,
  SUM(CASE WHEN h.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT h.hadm_id), 0) AS high_risk_mortality_rate,
  AVG(h.los_days) AS high_risk_mean_los_days,

  -- General inpatients metrics
  COUNT(DISTINCT g.hadm_id) AS general_admission_count,
  SUM(CASE WHEN g.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT g.hadm_id), 0) AS general_mortality_rate,
  AVG(g.los_days) AS general_mean_los_days,

  -- Critical lab rates comparison
  (SELECT high_glucose_rate FROM high_risk_lab_rates) AS high_risk_high_glucose_rate,
  (SELECT high_glucose_rate FROM general_lab_rates) AS general_high_glucose_rate,

  (SELECT high_sodium_rate FROM high_risk_lab_rates) AS high_risk_high_sodium_rate,
  (SELECT high_sodium_rate FROM general_lab_rates) AS general_high_sodium_rate,

  (SELECT abnormal_potassium_rate FROM high_risk_lab_rates) AS high_risk_abnormal_potassium_rate,
  (SELECT abnormal_potassium_rate FROM general_lab_rates) AS general_abnormal_potassium_rate,

  (SELECT high_creatinine_rate FROM high_risk_lab_rates) AS high_risk_high_creatinine_rate,
  (SELECT high_creatinine_rate FROM general_lab_rates) AS general_high_creatinine_rate

FROM high_risk_admissions h
CROSS JOIN general_inpatients g
LIMIT 1;