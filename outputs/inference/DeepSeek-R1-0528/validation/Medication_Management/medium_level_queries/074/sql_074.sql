WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    -- Diabetes diagnosis (ICD-9: 250.x; ICD-10: E10-E14)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE 
        d.hadm_id = a.hadm_id 
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%') 
          OR (d.icd_version = 10 AND d.icd_code LIKE 'E1%')
        )
    )
    -- Heart failure diagnosis (ICD-9: 428.x; ICD-10: I50.x)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE 
        d.hadm_id = a.hadm_id 
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%') 
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
glp1_orders AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    c.admittime,
    c.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort c
    ON p.hadm_id = c.hadm_id
  WHERE 
    -- Match GLP-1 agonists by drug name
    (LOWER(p.drug) LIKE '%exenatide%'
      OR LOWER(p.drug) LIKE '%liraglutide%'
      OR LOWER(p.drug) LIKE '%dulaglutide%'
      OR LOWER(p.drug) LIKE '%semaglutide%'
      OR LOWER(p.drug) LIKE '%lixisenatide%'
      OR LOWER(p.drug) LIKE '%albiglutide%')
    -- Subcutaneous route
    AND (LOWER(p.route) LIKE '%subq%'
      OR LOWER(p.route) LIKE '%subcut%'
      OR LOWER(p.route) LIKE '%subcutaneous%')
),
per_admission_flags AS (
  SELECT 
    c.hadm_id,
    -- Flag if any GLP-1 order in first 24h
    MAX(CASE 
          WHEN g.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) 
          THEN 1 ELSE 0 
        END) AS in_first_24h,
    -- Flag if any GLP-1 order in final 12h
    MAX(CASE 
          WHEN g.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime 
          THEN 1 ELSE 0 
        END) AS in_final_12h
  FROM cohort c
  LEFT JOIN glp1_orders g
    ON c.hadm_id = g.hadm_id
  GROUP BY c.hadm_id
)
SELECT 
  COUNT(*) AS total_admissions,
  SUM(in_first_24h) AS count_first_24h,
  SUM(in_final_12h) AS count_final_12h,
  ROUND(100.0 * SUM(in_first_24h) / COUNT(*), 2) AS prevalence_first_24h,
  ROUND(100.0 * SUM(in_final_12h) / COUNT(*), 2) AS prevalence_final_12h
FROM per_admission_flags;