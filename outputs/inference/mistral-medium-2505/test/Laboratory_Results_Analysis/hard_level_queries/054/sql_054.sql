WITH
-- Define AMI ICD codes (ICD-10 and ICD-9)
ami_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I21.%' OR icd_code LIKE '410.%'
),

-- Get female patients aged 38-48 with AMI
ami_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN ami_codes ac ON d.icd_code = ac.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND p.anchor_age IS NOT NULL
),

-- Get age-matched controls (female, 38-48, no AMI)
control_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND p.anchor_age IS NOT NULL
    AND a.hadm_id NOT IN (SELECT hadm_id FROM ami_patients)
),

-- Define critical lab thresholds
critical_labs AS (
  SELECT
    itemid,
    CASE
      WHEN label LIKE '%Troponin%' THEN 0.1
      WHEN label LIKE '%Creatinine%' THEN 2.0
      WHEN label LIKE '%Potassium%' THEN 5.5
      WHEN label LIKE '%Sodium%' THEN 150
      WHEN label LIKE '%Glucose%' THEN 200
      ELSE NULL
    END AS critical_threshold
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin%'
     OR label LIKE '%Creatinine%'
     OR label LIKE '%Potassium%'
     OR label LIKE '%Sodium%'
     OR label LIKE '%Glucose%'
),

-- Calculate lab instability score for AMI patients
ami_lab_scores AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    COUNT(DISTINCT CASE WHEN le.valuenum > cl.critical_threshold THEN le.itemid END) AS instability_score
  FROM ami_patients l
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON l.subject_id = le.subject_id AND l.hadm_id = le.hadm_id
  JOIN critical_labs cl ON le.itemid = cl.itemid
  WHERE TIMESTAMP_DIFF(le.charttime, l.admittime, HOUR) <= 72
    AND le.valuenum IS NOT NULL
    AND cl.critical_threshold IS NOT NULL
  GROUP BY l.subject_id, l.hadm_id
),

-- Calculate lab instability score for controls
control_lab_scores AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    COUNT(DISTINCT CASE WHEN le.valuenum > cl.critical_threshold THEN le.itemid END) AS instability_score
  FROM control_patients l
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON l.subject_id = le.subject_id AND l.hadm_id = le.hadm_id
  JOIN critical_labs cl ON le.itemid = cl.itemid
  WHERE TIMESTAMP_DIFF(le.charttime, l.admittime, HOUR) <= 72
    AND le.valuenum IS NOT NULL
    AND cl.critical_threshold IS NOT NULL
  GROUP BY l.subject_id, l.hadm_id
),

-- Stratify AMI patients into quartiles
ami_quartiles AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los_days,
    a.hospital_expire_flag,
    l.instability_score,
    NTILE(4) OVER (ORDER BY l.instability_score) AS quartile
  FROM ami_patients a
  JOIN ami_lab_scores l ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
),

-- Aggregate results by quartile
quartile_results AS (
  SELECT
    quartile,
    COUNT(*) AS patient_count,
    AVG(los_days) AS avg_los,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
    ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mortality_rate
  FROM ami_quartiles
  GROUP BY quartile
),

-- Aggregate results for controls
control_results AS (
  SELECT
    COUNT(*) AS patient_count,
    AVG(los_days) AS avg_los,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
    ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mortality_rate,
    AVG(instability_score) AS avg_instability_score
  FROM control_patients c
  JOIN control_lab_scores l ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
)

-- Final results
SELECT
  'AMI Patients' AS group_name,
  quartile,
  patient_count,
  avg_los,
  mortality_count,
  mortality_rate
FROM quartile_results

UNION ALL

SELECT
  'Control Group' AS group_name,
  NULL AS quartile,
  patient_count,
  avg_los,
  mortality_count,
  mortality_rate
FROM control_results
ORDER BY group_name, quartile;