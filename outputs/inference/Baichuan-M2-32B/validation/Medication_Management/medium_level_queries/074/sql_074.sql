WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 48 AND 58
),
diagnoses AS (
  SELECT 
    d.hadm_id,
    MAX(CASE WHEN d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN d.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS has_heart_failure
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10
  GROUP BY d.hadm_id
),
glp1_starts AS (
  SELECT 
    p.hadm_id,
    MIN(p.starttime) AS first_glp1_start
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.hadm_id = a.hadm_id
  WHERE p.drug LIKE '%GLP-1%' 
    OR p.drug IN ('semaglutide', 'liraglutide', 'dulaglutide', 'exenatide', 'tirzepatide')
    AND p.route IN ('SC', 'SubQ', 'Subcutaneous')
    AND p.starttime BETWEEN a.admittime AND a.dischtime
  GROUP BY p.hadm_id
)
SELECT 
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN g.first_glp1_start BETWEEN c.admittime AND LEAST(c.admittime + INTERVAL 24 HOUR, c.dischtime) THEN 1 ELSE 0 END) AS count_first_24h,
  SUM(CASE WHEN g.first_glp1_start BETWEEN GREATEST(c.admittime, c.dischtime - INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS count_final_12h,
  (SUM(CASE WHEN g.first_glp1_start BETWEEN c.admittime AND LEAST(c.admittime + INTERVAL 24 HOUR, c.dischtime) THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS prevalence_first_24h,
  (SUM(CASE WHEN g.first_glp1_start BETWEEN GREATEST(c.admittime, c.dischtime - INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS prevalence_final_12h
FROM cohort c
INNER JOIN diagnoses d 
  ON c.hadm_id = d.hadm_id
LEFT JOIN glp1_starts g 
  ON c.hadm_id = g.hadm_id
WHERE d.has_diabetes = 1 
  AND d.has_heart_failure = 1;