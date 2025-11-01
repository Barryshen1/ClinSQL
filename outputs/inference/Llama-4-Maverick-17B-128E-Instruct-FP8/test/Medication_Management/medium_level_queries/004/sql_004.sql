WITH 
-- Step 1: Identify relevant patient population
patient_cohort AS (
  SELECT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 45 AND 55
),

-- Step 2: Identify patients with T2DM and Heart Failure
diagnoses AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Type 2 diabetes mellitus%' OR dicd.long_title LIKE '%Heart failure%'
),

-- Step 3: Filter prescriptions for GLP-1 receptor agonists
glp1_prescriptions AS (
  SELECT p.hadm_id, p.starttime, p.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE LOWER(p.drug) LIKE '%glp-1%' OR LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' 
    OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%exenatide%'
),

-- Step 4: Analyze GLP-1 initiation and usage
glp1_analysis AS (
  SELECT pc.hadm_id, pc.admittime, pc.dischtime,
         MIN(CASE WHEN gp.starttime <= TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS glp1_started_within_72h,
         MAX(CASE WHEN gp.starttime <= pc.dischtime AND gp.starttime >= TIMESTAMP_SUB(pc.dischtime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS glp1_used_in_last_48h
  FROM patient_cohort pc
  LEFT JOIN glp1_prescriptions gp ON pc.hadm_id = gp.hadm_id
  WHERE pc.hadm_id IN (SELECT hadm_id FROM diagnoses)
  GROUP BY pc.hadm_id, pc.admittime, pc.dischtime
)

-- Final calculations
SELECT 
  COUNT(CASE WHEN glp1_started_within_72h = 1 THEN hadm_id END) / COUNT(hadm_id) * 100 AS percent_glp1_started_within_72h,
  COUNT(CASE WHEN glp1_used_in_last_48h = 1 THEN hadm_id END) / COUNT(hadm_id) * 100 AS percent_glp1_used_in_last_48h,
  (COUNT(CASE WHEN glp1_used_in_last_48h = 1 THEN hadm_id END) - COUNT(CASE WHEN glp1_started_within_72h = 1 THEN hadm_id END)) / COUNT(hadm_id) * 100 AS net_change
FROM glp1_analysis;