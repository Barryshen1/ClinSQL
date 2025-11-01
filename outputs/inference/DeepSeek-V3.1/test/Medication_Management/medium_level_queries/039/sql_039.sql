WITH cohort AS (
  -- Get males aged 52-62 with T2DM and heart failure
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND adm.hadm_id IN (
      -- T2DM: ICD10 E11
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code LIKE 'E11%' AND icd_version = 10
    )
    AND adm.hadm_id IN (
      -- Heart failure: ICD10 I50
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code LIKE 'I50%' AND icd_version = 10
    )
), 
glp1_orders AS (
  -- Get GLP-1 prescriptions for the cohort
  SELECT pr.subject_id, pr.hadm_id, pr.starttime, pr.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN cohort c
    ON pr.hadm_id = c.hadm_id
  WHERE LOWER(pr.drug) LIKE '%exenatide%' 
     OR LOWER(pr.drug) LIKE '%liraglutide%' 
     OR LOWER(pr.drug) LIKE '%dulaglutide%' 
     OR LOWER(pr.drug) LIKE '%semaglutide%'
    AND (LOWER(pr.route) LIKE '%inject%' OR LOWER(pr.route) LIKE '%iv%')
),
first_24h AS (
  -- Check if GLP-1 given in first 24h
  SELECT c.hadm_id,
    MAX(CASE WHEN go.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS glp1_first24h
  FROM cohort c
  LEFT JOIN glp1_orders go
    ON c.hadm_id = go.hadm_id
  GROUP BY c.hadm_id
),
final_48h AS (
  -- Check if GLP-1 given in final 48h
  SELECT c.hadm_id,
    MAX(CASE WHEN go.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS glp1_final48h
  FROM cohort c
  LEFT JOIN glp1_orders go
    ON c.hadm_id = go.hadm_id
  GROUP BY c.hadm_id
),
combined AS (
  SELECT 
    f24.hadm_id,
    f24.glp1_first24h,
    f48.glp1_final48h
  FROM first_24h f24
  INNER JOIN final_48h f48
    ON f24.hadm_id = f48.hadm_id
)
SELECT 
  COUNT(*) AS total_patients,
  SUM(glp1_first24h) AS count_first24h,
  SUM(glp1_final48h) AS count_final48h,
  ROUND(100 * SUM(glp1_first24h) / COUNT(*), 2) AS prevalence_first24h,
  ROUND(100 * SUM(glp1_final48h) / COUNT(*), 2) AS prevalence_final48h,
  ROUND(100 * (SUM(glp1_final48h) - SUM(glp1_first24h)) / COUNT(*), 2) AS absolute_change,
  ROUND(100 * (SUM(glp1_final48h) - SUM(glp1_first24h)) / NULLIF(SUM(glp1_first24h), 0), 2) AS relative_change
FROM combined;