WITH 
-- Define GLP-1 receptor agonists
glp1_agonists AS (
  SELECT drug 
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` 
  WHERE drug LIKE '%GLP-1%' OR drug LIKE '%exenatide%' OR drug LIKE '%liraglutide%' OR drug LIKE '%dulaglutide%' OR drug LIKE '%semaglutide%'
  GROUP BY drug
),

-- Identify population of interest
population AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code IN ('E11.9', 'E11.10', 'E11.20', 'E11.21', 'E11.22', 'E11.28', 'E11.29')  -- Type 2 diabetes codes
    )
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code IN ('I50.9', 'I50.1', 'I50.2', 'I50.3')  -- Heart failure codes
    )
),

-- First 12 hours GLP-1 initiation
early_glp1 AS (
  SELECT 
    p.hadm_id
  FROM 
    population p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
  ON 
    p.hadm_id = pr.hadm_id
  WHERE 
    pr.drug IN (SELECT drug FROM glp1_agonists)
    AND pr.starttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 12 HOUR)
),

-- Last 24 hours GLP-1 initiation
late_glp1 AS (
  SELECT 
    p.hadm_id
  FROM 
    population p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
  ON 
    p.hadm_id = pr.hadm_id
  WHERE 
    pr.drug IN (SELECT drug FROM glp1_agonists)
    AND pr.starttime BETWEEN TIMESTAMP_SUB(p.dischtime, INTERVAL 24 HOUR) AND p.dischtime
)

-- Calculate percentages and net change
SELECT 
  COUNT(DISTINCT p.hadm_id) AS population_count,
  COUNT(DISTINCT e.hadm_id) AS early_initiation_count,
  COUNT(DISTINCT l.hadm_id) AS late_initiation_count,
  SAFE_DIVIDE(COUNT(DISTINCT e.hadm_id), COUNT(DISTINCT p.hadm_id)) * 100 AS early_initiation_percent,
  SAFE_DIVIDE(COUNT(DISTINCT l.hadm_id), COUNT(DISTINCT p.hadm_id)) * 100 AS late_initiation_percent,
  SAFE_DIVIDE(COUNT(DISTINCT l.hadm_id), COUNT(DISTINCT p.hadm_id)) * 100 
  - SAFE_DIVIDE(COUNT(DISTINCT e.hadm_id), COUNT(DISTINCT p.hadm_id)) * 100 AS net_percentage_point_change
FROM 
  population p
  LEFT JOIN early_glp1 e ON p.hadm_id = e.hadm_id
  LEFT JOIN late_glp1 l ON p.hadm_id = l.hadm_id;