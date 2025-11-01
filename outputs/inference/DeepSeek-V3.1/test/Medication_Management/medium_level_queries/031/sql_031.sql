WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.hadm_id IN (
      SELECT di.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE (
        di.icd_code LIKE 'E11%'  -- Diabetes mellitus type 2
        OR di.icd_code LIKE 'I50%'  -- Heart failure
      )
      AND di.icd_version = 10
      GROUP BY di.hadm_id
      HAVING COUNT(DISTINCT 
        CASE WHEN di.icd_code LIKE 'E11%' THEN 'diabetes' 
             WHEN di.icd_code LIKE 'I50%' THEN 'hf' 
        END
      ) = 2  -- Has both diabetes and heart failure
    )
),

glp1_early AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.hadm_id = rx.hadm_id
  WHERE (LOWER(rx.drug) LIKE '%exenatide%'
     OR LOWER(rx.drug) LIKE '%liraglutide%'
     OR LOWER(rx.drug) LIKE '%semaglutide%'
     OR LOWER(rx.drug) LIKE '%dulaglutide%'
     OR LOWER(rx.drug) LIKE '%lixisenatide%'
     OR LOWER(rx.drug) LIKE '%albiglutide%')
  AND LOWER(rx.route) LIKE '%inj%'  -- Injectable route
  AND rx.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),

glp1_late AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.hadm_id = rx.hadm_id
  WHERE (LOWER(rx.drug) LIKE '%exenatide%'
     OR LOWER(rx.drug) LIKE '%liraglutide%'
     OR LOWER(rx.drug) LIKE '%semaglutide%'
     OR LOWER(rx.drug) LIKE '%dulaglutide%'
     OR LOWER(rx.drug) LIKE '%lixisenatide%'
     OR LOWER(rx.drug) LIKE '%albiglutide%')
  AND LOWER(rx.route) LIKE '%inj%'
  AND rx.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
)

SELECT 
  COUNT(DISTINCT c.hadm_id) AS total_admissions,
  COUNT(DISTINCT e.hadm_id) AS early_initiation,
  COUNT(DISTINCT l.hadm_id) AS late_initiation,
  ROUND(100 * COUNT(DISTINCT e.hadm_id) / COUNT(DISTINCT c.hadm_id), 2) AS pct_early,
  ROUND(100 * COUNT(DISTINCT l.hadm_id) / COUNT(DISTINCT c.hadm_id), 2) AS pct_late
FROM cohort c
LEFT JOIN glp1_early e ON c.hadm_id = e.hadm_id
LEFT JOIN glp1_late l ON c.hadm_id = l.hadm_id;