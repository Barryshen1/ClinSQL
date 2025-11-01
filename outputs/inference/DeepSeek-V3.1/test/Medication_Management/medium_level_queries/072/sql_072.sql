WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 79 AND 89
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND diag.icd_code LIKE 'E11%'  -- Type 2 diabetes
        AND diag.icd_version = 10
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND (diag.icd_code LIKE 'I50%'   -- Heart failure codes
             OR diag.icd_code = 'I11.0'
             OR diag.icd_code = 'I13.0'
             OR diag.icd_code = 'I13.2')
        AND diag.icd_version = 10
    )
),

glp1_first_12h AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS received_glp1
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id
    AND c.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%liraglutide%'
     OR LOWER(pr.drug) LIKE '%semaglutide%'
     OR LOWER(pr.drug) LIKE '%dulaglutide%'
     OR LOWER(pr.drug) LIKE '%exenatide%'
  GROUP BY c.subject_id, c.hadm_id
),

glp1_last_24h AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS received_glp1
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id
    AND c.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%liraglutide%'
     OR LOWER(pr.drug) LIKE '%semaglutide%'
     OR LOWER(pr.drug) LIKE '%dulaglutide%'
     OR LOWER(pr.drug) LIKE '%exenatide%'
  GROUP BY c.subject_id, c.hadm_id
)

SELECT 
  COUNT(*) AS total_patients,
  ROUND(100.0 * SUM(f.received_glp1) / COUNT(*), 2) AS percent_first_12h,
  ROUND(100.0 * SUM(l.received_glp1) / COUNT(*), 2) AS percent_last_24h,
  ROUND(100.0 * SUM(l.received_glp1) / COUNT(*) - 100.0 * SUM(f.received_glp1) / COUNT(*), 2) AS net_change_percentage_points
FROM cohort c
LEFT JOIN glp1_first_12h f
  ON c.subject_id = f.subject_id AND c.hadm_id = f.hadm_id
LEFT JOIN glp1_last_24h l
  ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id;