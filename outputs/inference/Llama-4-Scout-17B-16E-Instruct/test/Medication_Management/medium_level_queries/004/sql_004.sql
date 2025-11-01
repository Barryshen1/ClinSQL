WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' AND
    p.anchor_age BETWEEN 45 AND 55
),

-- Identify patients with T2DM and heart failure
patients_with_conditions AS (
  SELECT 
    poi.subject_id,
    poi.hadm_id,
    poi.admittime,
    poi.dischtime
  FROM 
    patients_of_interest poi
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON 
    poi.hadm_id = di.hadm_id
  WHERE 
    di.icd_code IN (
      '250.0', '250.01', '250.02', '250.03', '250.1', '250.11', '250.12', '250.13', 
      '250.2', '250.21', '250.22', '250.23', '250.3', '250.31', '250.32', '250.33', 
      '250.4', '250.41', '250.42', '250.43', '250.5', '250.51', '250.52', '250.53', 
      '250.6', '250.61', '250.62', '250.63', '250.7', '250.71', '250.72', '250.73', 
      '250.8', '250.81', '250.82', '250.83', '250.9', '250.91', '250.92', '250.93' 
      -- ICD-9 codes for T2DM
    ) 
    OR di.icd_code IN ('402.11', '402.21', '402.31', '404.11', '404.21', '404.31', '404.91', '404.92', '404.93')
    -- ICD-9 codes for heart failure
),

-- Identify patients started on GLP-1 within 72h
glp1_started_within_72h AS (
  SELECT 
    p.hadm_id
  FROM 
    patients_with_conditions p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON 
    p.hadm_id = pr.hadm_id
  WHERE 
    (pr.drug LIKE '%GLP-1%' 
     OR pr.drug LIKE '%exenatide%' 
     OR pr.drug LIKE '%liraglutide%' 
     OR pr.drug LIKE '%dulaglutide%' 
     OR pr.drug LIKE '%semaglutide%' 
     OR pr.drug LIKE '%albiglutide%')
    AND pr.starttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 72 HOUR)
),

-- Identify patients on GLP-1 in last 48h
glp1_last_48h AS (
  SELECT 
    p.hadm_id
  FROM 
    patients_with_conditions p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  ON 
    p.hadm_id = ph.hadm_id
  WHERE 
    (ph.medication LIKE '%GLP-1%' 
     OR ph.medication LIKE '%exenatide%' 
     OR ph.medication LIKE '%liraglutide%' 
     OR ph.medication LIKE '%dulaglutide%' 
     OR ph.medication LIKE '%semaglutide%' 
     OR ph.medication LIKE '%albiglutide%')
    AND ph.stoptime BETWEEN TIMESTAMP_SUB(p.dischtime, INTERVAL 48 HOUR) AND p.dischtime
)

-- Calculate percentages
SELECT 
  COUNT(DISTINCT CASE WHEN glp1_start.hadm_id IS NOT NULL THEN glp1_start.hadm_id END) * 100.0 / COUNT(DISTINCT pwc.hadm_id) AS pct_glp1_started_within_72h,
  COUNT(DISTINCT CASE WHEN glp1_last.hadm_id IS NOT NULL THEN glp1_last.hadm_id END) * 100.0 / COUNT(DISTINCT pwc.hadm_id) AS pct_glp1_last_48h,
  COUNT(DISTINCT CASE WHEN glp1_last.hadm_id IS NOT NULL THEN glp1_last.hadm_id END) * 100.0 / COUNT(DISTINCT pwc.hadm_id) - 
  COUNT(DISTINCT CASE WHEN glp1_start.hadm_id IS NOT NULL THEN glp1_start.hadm_id END) * 100.0 / COUNT(DISTINCT pwc.hadm_id) AS net_change
FROM 
  patients_with_conditions pwc
  LEFT JOIN glp1_started_within_72h glp1_start ON pwc.hadm_id = glp1_start.hadm_id
  LEFT JOIN glp1_last_48h glp1_last ON pwc.hadm_id = glp1_last.hadm_id;