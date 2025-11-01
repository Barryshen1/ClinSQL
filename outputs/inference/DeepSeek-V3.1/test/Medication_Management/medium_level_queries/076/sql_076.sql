WITH cohort AS (
  SELECT DISTINCT adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 75 AND 85
    AND pat.gender = 'F'
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 36
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE adm.hadm_id = diag.hadm_id
        AND adm.subject_id = diag.subject_id
        AND diag.icd_version = 10
        AND (diag.icd_code LIKE 'E10%' OR diag.icd_code LIKE 'E11%' OR diag.icd_code LIKE 'E13%')
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE adm.hadm_id = diag.hadm_id
        AND adm.subject_id = diag.subject_id
        AND diag.icd_version = 10
        AND (diag.icd_code LIKE 'I50.2%' OR diag.icd_code LIKE 'I50.3%' OR diag.icd_code LIKE 'I50.4%')
    )
),
glp1_first24h AS (
  SELECT DISTINCT cohort.hadm_id
  FROM cohort
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON cohort.hadm_id = rx.hadm_id
  WHERE (LOWER(rx.drug) LIKE '%exenatide%'
     OR LOWER(rx.drug) LIKE '%liraglutide%'
     OR LOWER(rx.drug) LIKE '%dulaglutide%'
     OR LOWER(rx.drug) LIKE '%semaglutide%'
     OR LOWER(rx.drug) LIKE '%lixisenatide%'
     OR LOWER(rx.drug) LIKE '%albiglutide%')
  AND (LOWER(rx.route) LIKE '%subq%'
     OR LOWER(rx.route) LIKE '%iv%'
     OR LOWER(rx.route) LIKE '%inject%')
  AND rx.starttime BETWEEN cohort.admittime AND DATETIME_ADD(cohort.admittime, INTERVAL 24 HOUR)
),
glp1_final12h AS (
  SELECT DISTINCT cohort.hadm_id
  FROM cohort
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON cohort.hadm_id = rx.hadm_id
  WHERE (LOWER(rx.drug) LIKE '%exenatide%'
     OR LOWER(rx.drug) LIKE '%liraglutide%'
     OR LOWER(rx.drug) LIKE '%dulaglutide%'
     OR LOWER(rx.drug) LIKE '%semaglutide%'
     OR LOWER(rx.drug) LIKE '%lixisenatide%'
     OR LOWER(rx.drug) LIKE '%albiglutide%')
  AND (LOWER(rx.route) LIKE '%subq%'
     OR LOWER(rx.route) LIKE '%iv%'
     OR LOWER(rx.route) LIKE '%inject%')
  AND rx.starttime BETWEEN DATETIME_SUB(cohort.dischtime, INTERVAL 12 HOUR) AND cohort.dischtime
)
SELECT 
  COUNT(*) AS total_admissions,
  COUNT(glp1_first24h.hadm_id) AS glp1_first24h_count,
  ROUND(COUNT(glp1_first24h.hadm_id) * 100.0 / COUNT(*), 2) AS glp1_first24h_percent,
  COUNT(glp1_final12h.hadm_id) AS glp1_final12h_count,
  ROUND(COUNT(glp1_final12h.hadm_id) * 100.0 / COUNT(*), 2) AS glp1_final12h_percent
FROM cohort
LEFT JOIN glp1_first24h ON cohort.hadm_id = glp1_first24h.hadm_id
LEFT JOIN glp1_final12h ON cohort.hadm_id = glp1_final12h.hadm_id;