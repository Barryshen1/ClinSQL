WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.anchor_age BETWEEN 50 AND 60
    AND pat.gender = 'F'
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 72
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND diag.icd_code LIKE 'E11%'
        AND diag.icd_version = 10
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND diag.icd_code LIKE 'I50%'
        AND diag.icd_version = 10
    )
),
glp1_drugs AS (
  SELECT 
    subject_id,
    hadm_id,
    starttime,
    stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%exenatide%'
    OR LOWER(drug) LIKE '%liraglutide%'
    OR LOWER(drug) LIKE '%semaglutide%'
    OR LOWER(drug) LIKE '%dulaglutide%'
    OR LOWER(drug) LIKE '%glp%'
),
first_12h AS (
  SELECT 
    c.subject_id,
    COUNT(DISTINCT g.subject_id) AS initiated_glp1
  FROM cohort c
  LEFT JOIN glp1_drugs g
    ON c.subject_id = g.subject_id
      AND c.hadm_id = g.hadm_id
      AND g.starttime BETWEEN c.admittime 
          AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
  GROUP BY c.subject_id
),
final_72h AS (
  SELECT 
    c.subject_id,
    COUNT(DISTINCT g.subject_id) AS on_glp1_final
  FROM cohort c
  LEFT JOIN glp1_drugs g
    ON c.subject_id = g.subject_id
      AND c.hadm_id = g.hadm_id
      AND g.starttime <= c.dischtime
      AND (g.stoptime IS NULL OR g.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR))
  GROUP BY c.subject_id
)
SELECT 
  COUNT(DISTINCT c.subject_id) AS total_patients,
  SUM(f12.initiated_glp1) AS initiated_in_first_12h,
  SUM(f72.on_glp1_final) AS on_glp1_in_final_72h,
  ROUND(100.0 * SUM(f12.initiated_glp1) / COUNT(DISTINCT c.subject_id), 2) AS pct_initiated,
  ROUND(100.0 * SUM(f72.on_glp1_final) / COUNT(DISTINCT c.subject_id), 2) AS pct_final,
  ROUND(100.0 * (SUM(f72.on_glp1_final) - SUM(f12.initiated_glp1)) / COUNT(DISTINCT c.subject_id), 2) AS net_change_pct_points
FROM cohort c
LEFT JOIN first_12h f12 ON c.subject_id = f12.subject_id
LEFT JOIN final_72h f72 ON c.subject_id = f72.subject_id;