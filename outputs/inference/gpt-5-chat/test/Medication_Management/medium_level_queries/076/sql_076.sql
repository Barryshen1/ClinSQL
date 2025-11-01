WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 36
),
dx AS (
  SELECT dx.hadm_id,
         MAX(
           CASE 
             WHEN ((dx.icd_version = 9 AND dx.icd_code LIKE '250%')
               OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'E10%' OR dx.icd_code LIKE 'E11%' OR dx.icd_code LIKE 'E13%' OR dx.icd_code LIKE 'E14%')))
             THEN 1 ELSE 0 
           END
         ) AS has_diabetes,
         MAX(
           CASE 
             WHEN ((dx.icd_version = 9 AND (dx.icd_code LIKE '4282%' OR dx.icd_code LIKE '4283%'))
               OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'I50.2%' OR dx.icd_code LIKE 'I50.3%')))
             THEN 1 ELSE 0 
           END
         ) AS has_ahf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  GROUP BY dx.hadm_id
),
cohort_with_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN dx
    ON c.hadm_id = dx.hadm_id
  WHERE dx.has_diabetes = 1 AND dx.has_ahf = 1
),
glp1_prescriptions AS (
  SELECT pr.subject_id, pr.hadm_id, pr.starttime, pr.route
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE LOWER(pr.drug) LIKE '%liraglutide%'
     OR LOWER(pr.drug) LIKE '%exenatide%'
     OR LOWER(pr.drug) LIKE '%dulaglutide%'
     OR LOWER(pr.drug) LIKE '%semaglutide%'
     OR LOWER(pr.drug) LIKE '%albiglutide%'
),
glp1_inj AS (
  SELECT g.subject_id, g.hadm_id, g.starttime
  FROM glp1_prescriptions g
  WHERE LOWER(g.route) LIKE '%sc%' OR LOWER(g.route) LIKE '%subcut%'
),
early_start AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort_with_dx c
  JOIN glp1_inj g
    ON c.hadm_id = g.hadm_id
   AND TIMESTAMP_DIFF(g.starttime, c.admittime, HOUR) BETWEEN 0 AND 24
),
late_start AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort_with_dx c
  JOIN glp1_inj g
    ON c.hadm_id = g.hadm_id
   AND TIMESTAMP_DIFF(c.dischtime, g.starttime, HOUR) BETWEEN 0 AND 12
)
SELECT
  ROUND(100 * COUNT(DISTINCT early_start.hadm_id) / COUNT(DISTINCT c.hadm_id), 2) AS pct_early_start,
  ROUND(100 * COUNT(DISTINCT late_start.hadm_id) / COUNT(DISTINCT c.hadm_id), 2) AS pct_late_start
FROM cohort_with_dx c
LEFT JOIN early_start
  ON c.hadm_id = early_start.hadm_id
LEFT JOIN late_start
  ON c.hadm_id = late_start.hadm_id;