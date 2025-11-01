WITH
-- Define cardiac arrest ICD codes
cardiac_arrest_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I46.%'  -- ICD-10 cardiac arrest codes
     OR icd_code = '4275'      -- ICD-9 cardiac arrest code
),

-- Identify post-cardiac arrest patients (female, 52-62)
post_cardiac_arrest_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN cardiac_arrest_codes c ON d.icd_code = c.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),

-- Identify general inpatient comparison group (female, 52-62, no cardiac arrest)
general_inpatients AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND p.subject_id NOT IN (SELECT subject_id FROM post_cardiac_arrest_patients)
),

-- Define critical lab items for instability score
critical_lab_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN ('Lactate', 'pH', 'Glucose', 'Potassium', 'Sodium', 'BUN', 'Creatinine')
),

-- Get lab events within first 48 hours for post-cardiac arrest patients
post_ca_labs AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    d.label,
    TIMESTAMP_DIFF(l.charttime, p.admittime, HOUR) AS hours_since_admission
  FROM post_cardiac_arrest_patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON p.subject_id = l.subject_id AND p.hadm_id = l.hadm_id
  JOIN critical_lab_items c ON l.itemid = c.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE TIMESTAMP_DIFF(l.charttime, p.admittime, HOUR) <= 48
),

-- Get lab events within first 48 hours for general inpatients
general_inpatient_labs AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    d.label,
    TIMESTAMP_DIFF(l.charttime, p.admittime, HOUR) AS hours_since_admission
  FROM general_inpatients p
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON p.subject_id = l.subject_id AND p.hadm_id = l.hadm_id
  JOIN critical_lab_items c ON l.itemid = c.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE TIMESTAMP_DIFF(l.charttime, p.admittime, HOUR) <= 48
),

-- Calculate instability score components (simplified example)
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(CASE WHEN label = 'Lactate' AND valuenum > 2 THEN 1 END) +
    COUNT(CASE WHEN label = 'pH' AND valuenum < 7.35 THEN 1 END) +
    COUNT(CASE WHEN label = 'Glucose' AND (valuenum < 70 OR valuenum > 180) THEN 1 END) +
    COUNT(CASE WHEN label = 'Potassium' AND (valuenum < 3.5 OR valuenum > 5.0) THEN 1 END) AS instability_score
  FROM post_ca_labs
  GROUP BY subject_id, hadm_id
),

-- Calculate outcomes for both groups
outcomes AS (
  SELECT
    'Post-Cardiac Arrest' AS cohort,
    COUNT(DISTINCT subject_id) AS patient_count,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24) AS avg_los_days,
    SUM(hospital_expire_flag) AS deaths,
    SUM(hospital_expire_flag)/COUNT(DISTINCT subject_id) AS mortality_rate
  FROM post_cardiac_arrest_patients

  UNION ALL

  SELECT
    'General Inpatients' AS cohort,
    COUNT(DISTINCT subject_id) AS patient_count,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24) AS avg_los_days,
    SUM(hospital_expire_flag) AS deaths,
    SUM(hospital_expire_flag)/COUNT(DISTINCT subject_id) AS mortality_rate
  FROM general_inpatients
)

-- Final results restructured to avoid scalar subquery error
SELECT 'Instability Score IQR' AS metric_type,
       PERCENTILE_CONT(instability_score, 0.25) OVER() AS q1,
       PERCENTILE_CONT(instability_score, 0.5) OVER() AS median
FROM instability_scores
LIMIT 1

UNION ALL

SELECT 'Post-CA Lab Stats' AS metric_type,
       COUNT(DISTINCT subject_id) AS patients_with_labs,
       COUNT(*) AS total_labs,
       COUNT(*)/COUNT(DISTINCT hadm_id) AS labs_per_patient
FROM post_ca_labs

UNION ALL

SELECT 'General Inpatient Lab Stats' AS metric_type,
       COUNT(DISTINCT subject_id) AS patients_with_labs,
       COUNT(*) AS total_labs,
       COUNT(*)/COUNT(DISTINCT hadm_id) AS labs_per_patient
FROM general_inpatient_labs

UNION ALL

SELECT 'Outcome Comparison' AS metric_type,
       cohort AS cohort,
       patient_count,
       avg_los_days,
       deaths,
       mortality_rate
FROM outcomes;