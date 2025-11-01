WITH 
-- Step 1: Identify patients with Type 2 diabetes and heart failure
diabetes_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10 AND icd_code LIKE 'E11%'
),
heart_failure_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10 AND icd_code LIKE 'I50%'
),

-- Step 2: Filter patients based on age, gender, and hospital stay duration
cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime, icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.hadm_id IN (SELECT hadm_id FROM diabetes_patients)
    AND a.hadm_id IN (SELECT hadm_id FROM heart_failure_patients)
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),

-- Step 3: Assess GLP-1 receptor agonist prescriptions
glp1_prescriptions AS (
  SELECT c.hadm_id, 
         MIN(CASE WHEN DATETIME_DIFF(pr.starttime, c.intime, HOUR) <= 12 THEN 1 ELSE 0 END) AS glp1_initiated,
         MAX(CASE WHEN DATETIME_DIFF(pr.starttime, c.dischtime, HOUR) BETWEEN -72 AND 0 THEN 1 ELSE 0 END) AS glp1_final_72hr
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON c.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%glp-1%' OR LOWER(pr.drug) LIKE '%glucagon-like peptide-1%'
  GROUP BY c.hadm_id
)

-- Step 4: Calculate the required metrics
SELECT 
  COUNT(*) AS total_patients,
  SUM(glp1_initiated) AS glp1_initiated_count,
  AVG(glp1_initiated) * 100 AS glp1_initiation_rate,
  AVG(glp1_final_72hr) * 100 AS glp1_prevalence_final_72hr,
  (AVG(glp1_final_72hr) - AVG(glp1_initiated)) * 100 AS net_percentage_point_change
FROM glp1_prescriptions;