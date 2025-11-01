WITH
-- Define hepatic failure ICD codes
hepatic_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('5722', 'K720', 'K721', 'K729')  -- Example hepatic failure codes
),

-- Get patients with hepatic failure
hepatic_failure_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN hepatic_failure_codes hfc ON d.icd_code = hfc.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
),

-- Calculate first 48 hours for each admission
first_48_hours AS (
  SELECT
    hadm_id,
    admittime,
    TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) AS end_48_hours
  FROM hepatic_failure_patients
),

-- Get critical lab itemids and labels
critical_lab_itemids AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN ('Bilirubin', 'INR', 'Creatinine')
),

-- Get critical lab events during first 48 hours for hepatic failure patients
hepatic_labs_48h AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    COUNT(*) AS lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN first_48_hours f ON l.hadm_id = f.hadm_id
  JOIN critical_lab_itemids cli ON l.itemid = cli.itemid
  WHERE l.charttime BETWEEN f.admittime AND f.end_48_hours
  GROUP BY l.subject_id, l.hadm_id, l.itemid
),

-- Calculate instability score (example using SOFA components)
instability_score AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN c.itemid = 220180 THEN c.valuenum ELSE NULL END) AS bilirubin,
    MAX(CASE WHEN c.itemid = 220210 THEN c.valuenum ELSE NULL END) AS creatinine,
    MAX(CASE WHEN c.itemid = 220225 THEN c.valuenum ELSE NULL END) AS inr,
    -- Calculate composite score (example: sum of normalized values)
    (COALESCE(MAX(CASE WHEN c.itemid = 220180 THEN c.valuenum ELSE NULL END), 0) / 2) +
    (COALESCE(MAX(CASE WHEN c.itemid = 220210 THEN c.valuenum ELSE NULL END), 0) / 2) +
    (COALESCE(MAX(CASE WHEN c.itemid = 220225 THEN c.valuenum ELSE NULL END), 0) / 2) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN first_48_hours f ON c.hadm_id = f.hadm_id
  WHERE c.charttime BETWEEN f.admittime AND f.end_48_hours
    AND c.itemid IN (220180, 220210, 220225)  -- Example itemids for SOFA components
  GROUP BY c.subject_id, c.hadm_id
),

-- General inpatient comparison group (same age/gender but no hepatic failure)
general_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.hadm_id NOT IN (SELECT hadm_id FROM hepatic_failure_patients)
),

-- First 48 hours for general inpatients
general_first_48_hours AS (
  SELECT
    hadm_id,
    admittime,
    TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) AS end_48_hours
  FROM general_inpatients
),

-- Critical labs for general inpatients
general_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    COUNT(*) AS lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN general_first_48_hours gf ON l.hadm_id = gf.hadm_id
  JOIN critical_lab_itemids cli ON l.itemid = cli.itemid
  WHERE l.charttime BETWEEN gf.admittime AND gf.end_48_hours
  GROUP BY l.subject_id, l.hadm_id, l.itemid
),

-- Hepatic failure cohort metrics
hepatic_metrics AS (
  SELECT
    'Hepatic Failure' AS cohort,
    COUNT(DISTINCT h.subject_id) AS patient_count,
    MAX(i.instability_score) AS max_instability_score,
    SUM(CASE WHEN h.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
    AVG(TIMESTAMP_DIFF(h.dischtime, h.admittime, HOUR) / 24) AS avg_los_days,
    SUM(CASE WHEN hl.itemid = (SELECT itemid FROM critical_lab_itemids WHERE label = 'Bilirubin') THEN hl.lab_count ELSE 0 END) AS bilirubin_lab_count,
    SUM(CASE WHEN hl.itemid = (SELECT itemid FROM critical_lab_itemids WHERE label = 'Creatinine') THEN hl.lab_count ELSE 0 END) AS creatinine_lab_count,
    SUM(CASE WHEN hl.itemid = (SELECT itemid FROM critical_lab_itemids WHERE label = 'INR') THEN hl.lab_count ELSE 0 END) AS inr_lab_count
  FROM hepatic_failure_patients h
  LEFT JOIN instability_score i ON h.hadm_id = i.hadm_id
  LEFT JOIN hepatic_labs_48h hl ON h.hadm_id = hl.hadm_id
),

-- General inpatient comparison metrics
general_metrics AS (
  SELECT
    'General Inpatients' AS cohort,
    COUNT(DISTINCT g.subject_id) AS patient_count,
    NULL AS max_instability_score,
    SUM(CASE WHEN g.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
    AVG(TIMESTAMP_DIFF(g.dischtime, g.admittime, HOUR) / 24) AS avg_los_days,
    SUM(CASE WHEN gl.itemid = (SELECT itemid FROM critical_lab_itemids WHERE label = 'Bilirubin') THEN gl.lab_count ELSE 0 END) AS bilirubin_lab_count,
    SUM(CASE WHEN gl.itemid = (SELECT itemid FROM critical_lab_itemids WHERE label = 'Creatinine') THEN gl.lab_count ELSE 0 END) AS creatinine_lab_count,
    SUM(CASE WHEN gl.itemid = (SELECT itemid FROM critical_lab_itemids WHERE label = 'INR') THEN gl.lab_count ELSE 0 END) AS inr_lab_count
  FROM general_inpatients g
  LEFT JOIN general_labs gl ON g.hadm_id = gl.hadm_id
)

-- Final results combining both cohorts
SELECT * FROM hepatic_metrics
UNION ALL
SELECT * FROM general_metrics
ORDER BY cohort;