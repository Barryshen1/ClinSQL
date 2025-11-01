WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 58 AND 68
),

-- Step 2: Identify admissions for chest pain or AMI
ami_admissions AS (
  SELECT 
    c.hadm_id
  FROM 
    cohort c
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON c.hadm_id = d.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE 
    dicd.long_title LIKE '%myocardial infarction%' OR dicd.long_title LIKE '%chest pain%'
),

-- Step 3: Filter for initial Troponin T > 0.04 ng/mL
trop_positive AS (
  SELECT 
    l.hadm_id,
    MIN(l.valuenum) AS min_trop
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE 
    dl.label LIKE '%Troponin T%' AND l.valuenum > 0.04
  GROUP BY 
    l.hadm_id
  HAVING 
    MIN(l.valuenum) > 0.04
),

-- Combine the filters
final_cohort AS (
  SELECT 
    c.*
  FROM 
    cohort c
  JOIN 
    ami_admissions aa ON c.hadm_id = aa.hadm_id
  JOIN 
    trop_positive tp ON c.hadm_id = tp.hadm_id
)

-- Calculate summary statistics and in-hospital mortality rate
SELECT 
  COUNT(*) AS total_admissions,
  AVG(anchor_age) AS mean_age,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_rate,
  AVG(DATETIME_DIFF(dischtime, admittime, HOUR)) AS mean_length_of_stay_hours
FROM 
  final_cohort;