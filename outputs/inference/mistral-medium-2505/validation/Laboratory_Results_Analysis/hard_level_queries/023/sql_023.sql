WITH
-- Define AMI ICD codes
ami_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I21.%' OR icd_code LIKE 'I22.%'
),

-- Get female AMI admissions aged 90-100
female_ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN ami_icd_codes ami ON d.icd_code = ami.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    AND a.admission_type != 'NEWBORN'  -- Exclude newborn admissions
),

-- Define critical lab items
critical_lab_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN (
    'Lactate', 'Troponin I', 'Troponin T', 'Potassium',
    'Sodium', 'Hemoglobin', 'Platelet Count', 'INR(PT)'
  )
),

-- Get lab events within first 48 hours
early_lab_events AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    d.label,
    -- Define abnormal ranges for each lab
    CASE
      WHEN d.label = 'Lactate' AND l.valuenum > 2 THEN 1 ELSE 0 END AS lactate_abnormal,
    CASE
      WHEN d.label LIKE 'Troponin%' AND l.valuenum > 0.04 THEN 1 ELSE 0 END AS troponin_abnormal,
    CASE
      WHEN d.label = 'Potassium' AND (l.valuenum < 3.5 OR l.valuenum > 5.0) THEN 1 ELSE 0 END AS potassium_abnormal,
    CASE
      WHEN d.label = 'Sodium' AND (l.valuenum < 135 OR l.valuenum > 145) THEN 1 ELSE 0 END AS sodium_abnormal,
    CASE
      WHEN d.label = 'Hemoglobin' AND l.valuenum < 12 THEN 1 ELSE 0 END AS hemoglobin_abnormal,
    CASE
      WHEN d.label = 'Platelet Count' AND l.valuenum < 150 THEN 1 ELSE 0 END AS platelets_abnormal,
    CASE
      WHEN d.label = 'INR(PT)' AND l.valuenum > 1.1 THEN 1 ELSE 0 END AS inr_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN female_ami_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  JOIN critical_lab_items cli ON l.itemid = cli.itemid
  WHERE TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) <= 48
),

-- Calculate lab instability score per patient
patient_lab_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(lactate_abnormal) AS lactate_abnormal_count,
    SUM(troponin_abnormal) AS troponin_abnormal_count,
    SUM(potassium_abnormal) AS potassium_abnormal_count,
    SUM(sodium_abnormal) AS sodium_abnormal_count,
    SUM(hemoglobin_abnormal) AS hemoglobin_abnormal_count,
    SUM(platelets_abnormal) AS platelets_abnormal_count,
    SUM(inr_abnormal) AS inr_abnormal_count,
    -- Simple sum of abnormal labs as instability score
    SUM(
      lactate_abnormal + troponin_abnormal + potassium_abnormal +
      sodium_abnormal + hemoglobin_abnormal + platelets_abnormal + inr_abnormal
    ) AS lab_instability_score
  FROM early_lab_events
  GROUP BY subject_id, hadm_id
),

-- Calculate 75th percentile of lab instability score
p75_threshold AS (
  SELECT PERCENTILE_CONT(lab_instability_score, 0.75) OVER() AS p75_value
  FROM patient_lab_scores
  LIMIT 1
),

-- Get all female patients aged 90-100 (not just AMI)
all_female_90_100 AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    AND a.admission_type != 'NEWBORN'
),

-- Calculate critical lab rates for all female 90-100
all_female_lab_rates AS (
  SELECT
    a.hadm_id,
    MAX(CASE WHEN d.label = 'Lactate' THEN 1 ELSE 0 END) AS lactate_abnormal_count,
    MAX(CASE WHEN d.label LIKE 'Troponin%' THEN 1 ELSE 0 END) AS troponin_abnormal_count,
    MAX(CASE WHEN d.label = 'Potassium' THEN 1 ELSE 0 END) AS potassium_abnormal_count,
    MAX(CASE WHEN d.label = 'Sodium' THEN 1 ELSE 0 END) AS sodium_abnormal_count,
    MAX(CASE WHEN d.label = 'Hemoglobin' THEN 1 ELSE 0 END) AS hemoglobin_abnormal_count,
    MAX(CASE WHEN d.label = 'Platelet Count' THEN 1 ELSE 0 END) AS platelets_abnormal_count,
    MAX(CASE WHEN d.label = 'INR(PT)' THEN 1 ELSE 0 END) AS inr_abnormal_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN all_female_90_100 a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE d.label IN (
    'Lactate', 'Troponin I', 'Troponin T', 'Potassium',
    'Sodium', 'Hemoglobin', 'Platelet Count', 'INR(PT)'
  )
  GROUP BY a.hadm_id
),

-- Aggregate the lab rates for all female 90-100
all_female_lab_rates_agg AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS total_admissions,
    SUM(CASE WHEN lactate_abnormal_count > 0 THEN 1 ELSE 0 END) AS lactate_abnormal_admissions,
    SUM(CASE WHEN troponin_abnormal_count > 0 THEN 1 ELSE 0 END) AS troponin_abnormal_admissions,
    SUM(CASE WHEN potassium_abnormal_count > 0 THEN 1 ELSE 0 END) AS potassium_abnormal_admissions,
    SUM(CASE WHEN sodium_abnormal_count > 0 THEN 1 ELSE 0 END) AS sodium_abnormal_admissions,
    SUM(CASE WHEN hemoglobin_abnormal_count > 0 THEN 1 ELSE 0 END) AS hemoglobin_abnormal_admissions,
    SUM(CASE WHEN platelets_abnormal_count > 0 THEN 1 ELSE 0 END) AS platelets_abnormal_admissions,
    SUM(CASE WHEN inr_abnormal_count > 0 THEN 1 ELSE 0 END) AS inr_abnormal_admissions
  FROM all_female_lab_rates
)

-- Final results
SELECT
  '≥P75 Female AMI Patients' AS group_name,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(a.los_hours) AS mean_los_hours,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_deaths,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id) AS mortality_rate,
  -- Lab rates for ≥P75 group
  SUM(CASE WHEN l.lactate_abnormal_count > 0 THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id) AS lactate_abnormal_rate,
  SUM(CASE WHEN l.troponin_abnormal_count > 0 THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id) AS troponin_abnormal_rate,
  SUM(CASE WHEN l.potassium_abnormal_count > 0 THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id) AS potassium_abnormal_rate,
  SUM(CASE WHEN l.sodium_abnormal_count > 0 THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id) AS sodium_abnormal_rate,
  SUM(CASE WHEN l.hemoglobin_abnormal_count > 0 THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id) AS hemoglobin_abnormal_rate,
  SUM(CASE WHEN l.platelets_abnormal_count > 0 THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id) AS platelets_abnormal_rate,
  SUM(CASE WHEN l.inr_abnormal_count > 0 THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id) AS inr_abnormal_rate
FROM female_ami_admissions a
JOIN patient_lab_scores l ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
CROSS JOIN p75_threshold p
WHERE l.lab_instability_score >= p.p75_value

UNION ALL

SELECT
  'All Female Patients 90-100' AS group_name,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(a.los_hours) AS mean_los_hours,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_deaths,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id) AS mortality_rate,
  -- Lab rates for all female 90-100
  lactate_abnormal_admissions / total_admissions AS lactate_abnormal_rate,
  troponin_abnormal_admissions / total_admissions AS troponin_abnormal_rate,
  potassium_abnormal_admissions / total_admissions AS potassium_abnormal_rate,
  sodium_abnormal_admissions / total_admissions AS sodium_abnormal_rate,
  hemoglobin_abnormal_admissions / total_admissions AS hemoglobin_abnormal_rate,
  platelets_abnormal_admissions / total_admissions AS platelets_abnormal_rate,
  inr_abnormal_admissions / total_admissions AS inr_abnormal_rate
FROM all_female_90_100 a, all_female_lab_rates_agg l;