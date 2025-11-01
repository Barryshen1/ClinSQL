WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATETIME_ADD(adm.admittime, INTERVAL 48 HOUR) AS first_48h_end,
    DATETIME_SUB(adm.dischtime, INTERVAL 12 HOUR) AS final_12h_start
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 48
    AND adm.hadm_id IN (
      -- T2DM diagnosis
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code LIKE 'E11%' OR (icd_version = 9 AND icd_code LIKE '250%' AND (icd_code LIKE '%0' OR icd_code LIKE '%2'))
      INTERSECT DISTINCT
      -- Heart failure diagnosis
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code LIKE 'I50%' OR (icd_version = 9 AND icd_code LIKE '428%')
    )
),
glp1_first48 AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS glp1_first48 -- flag if at least one GLP-1 in first 48h
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime >= c.admittime 
    AND p.starttime <= c.first_48h_end
    AND LOWER(p.drug) LIKE '%exenatide%' 
    OR LOWER(p.drug) LIKE '%liraglutide%'
    OR LOWER(p.drug) LIKE '%dulaglutide%'
    OR LOWER(p.drug) LIKE '%semaglutide%'
    OR LOWER(p.drug) LIKE '%lixisenatide%'
    OR LOWER(p.drug) LIKE '%albiglutide%'
  GROUP BY c.hadm_id
),
glp1_final12 AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS glp1_final12 -- flag if at least one GLP-1 in final 12h
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime >= c.final_12h_start 
    AND p.starttime <= c.dischtime
    AND (LOWER(p.drug) LIKE '%exenatide%' 
      OR LOWER(p.drug) LIKE '%liraglutide%'
      OR LOWER(p.drug) LIKE '%dulaglutide%'
      OR LOWER(p.drug) LIKE '%semaglutide%'
      OR LOWER(p.drug) LIKE '%lixisenatide%'
      OR LOWER(p.drug) LIKE '%albiglutide%')
  GROUP BY c.hadm_id
),
cohort_glp1 AS (
  SELECT 
    c.hadm_id,
    COALESCE(f48.glp1_first48, 0) AS glp1_first48,
    COALESCE(f12.glp1_final12, 0) AS glp1_final12
  FROM cohort c
  LEFT JOIN glp1_first48 f48 ON c.hadm_id = f48.hadm_id
  LEFT JOIN glp1_final12 f12 ON c.hadm_id = f12.hadm_id
)
SELECT 
  COUNT(*) AS total_admissions,
  SUM(glp1_first48) AS count_first48,
  ROUND(100 * SUM(glp1_first48) / COUNT(*), 2) AS prevalence_first48,
  SUM(glp1_final12) AS count_final12,
  ROUND(100 * SUM(glp1_final12) / COUNT(*), 2) AS prevalence_final12,
  ROUND(100 * SUM(glp1_first48) / COUNT(*) - 100 * SUM(glp1_final12) / COUNT(*), 2) AS absolute_pp_difference
FROM cohort_glp1;