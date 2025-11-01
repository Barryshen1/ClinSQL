WITH
-- Define ACS ICD codes (I20-I25 range)
acs_icd_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code BETWEEN 'I20' AND 'I25'
),

-- Get female patients aged 53-63 with ACS
acs_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN acs_icd_codes acs ON d.icd_code = acs.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND p.anchor_year = EXTRACT(YEAR FROM a.admittime) - p.anchor_age
),

-- Define critical lab categories and their threshold ranges
critical_lab_categories AS (
  SELECT
    itemid,
    label AS category,
    CASE
      WHEN label = 'Potassium' THEN STRUCT(3.5 AS lower, 5.0 AS upper)
      WHEN label = 'Sodium' THEN STRUCT(135 AS lower, 145 AS upper)
      WHEN label = 'Glucose' THEN STRUCT(70 AS lower, 180 AS upper)
      WHEN label = 'Hemoglobin' THEN STRUCT(7 AS lower, 18 AS upper)
      WHEN label = 'WBC' THEN STRUCT(4 AS lower, 11 AS upper)
      WHEN label = 'Platelets' THEN STRUCT(150 AS lower, 450 AS upper)
      WHEN label = 'INR' THEN STRUCT(NULL AS lower, 4 AS upper)
      ELSE NULL
    END AS thresholds
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN ('Potassium', 'Sodium', 'Glucose', 'Hemoglobin', 'WBC', 'Platelets', 'INR')
),

-- Calculate lab instability score for ACS patients
acs_lab_scores AS (
  SELECT
    ap.subject_id,
    ap.hadm_id,
    COUNT(DISTINCT clc.category) AS lab_instability_score
  FROM acs_patients ap
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON ap.subject_id = le.subject_id AND ap.hadm_id = le.hadm_id
  JOIN critical_lab_categories clc ON le.itemid = clc.itemid
  WHERE le.charttime BETWEEN ap.admittime AND TIMESTAMP_ADD(ap.admittime, INTERVAL 72 HOUR)
    AND (
      (clc.thresholds.lower IS NOT NULL AND le.valuenum < clc.thresholds.lower) OR
      (clc.thresholds.upper IS NOT NULL AND le.valuenum > clc.thresholds.upper)
    )
  GROUP BY ap.subject_id, ap.hadm_id
),

-- Get quartiles for lab instability scores
quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    lab_instability_score,
    NTILE(4) OVER (ORDER BY lab_instability_score) AS quartile
  FROM acs_lab_scores
),

-- Calculate mortality and LOS by quartile
quartile_results AS (
  SELECT
    q.quartile,
    COUNT(DISTINCT q.subject_id) AS patient_count,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT q.subject_id) AS mortality_rate,
    AVG(a.los_hours / 24.0) AS avg_los_days
  FROM quartiles q
  JOIN acs_patients a ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
  GROUP BY q.quartile
  ORDER BY q.quartile
),

-- Get age-matched controls (female 53-63 without ACS)
control_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND p.anchor_year = EXTRACT(YEAR FROM a.admittime) - p.anchor_age
    AND p.subject_id NOT IN (SELECT subject_id FROM acs_patients)
),

-- Calculate critical lab rates for controls
control_lab_rates AS (
  SELECT
    COUNT(DISTINCT CASE WHEN
      (clc.thresholds.lower IS NOT NULL AND le.valuenum < clc.thresholds.lower) OR
      (clc.thresholds.upper IS NOT NULL AND le.valuenum > clc.thresholds.upper)
    THEN clc.category END) * 100.0 / COUNT(DISTINCT cp.subject_id) AS critical_lab_rate
  FROM control_patients cp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON cp.subject_id = le.subject_id AND cp.hadm_id = le.hadm_id
  JOIN critical_lab_categories clc ON le.itemid = clc.itemid
  WHERE le.charttime BETWEEN cp.admittime AND TIMESTAMP_ADD(cp.admittime, INTERVAL 72 HOUR)
)

-- Final results
SELECT
  qr.quartile,
  qr.patient_count,
  qr.mortality_rate,
  qr.avg_los_days,
  (SELECT critical_lab_rate FROM control_lab_rates) AS control_critical_lab_rate
FROM quartile_results qr;