WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),
diag_t2dm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE ( (d.icd_version = 9 AND (d.icd_code LIKE '250%0' OR d.icd_code LIKE '250%2'))
       OR (d.icd_version = 10 AND d.icd_code LIKE 'E11%') )
),
diag_hf AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE ( (d.icd_version = 9 AND d.icd_code LIKE '428%')
       OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') )
),
cohort_diag AS (
  SELECT c.*
  FROM cohort c
  JOIN diag_t2dm t2 ON c.hadm_id = t2.hadm_id
  JOIN diag_hf hf ON c.hadm_id = hf.hadm_id
),
glp1_admin AS (
  SELECT cd.hadm_id,
         MIN(TIMESTAMP_DIFF(pr.starttime, cd.admittime, HOUR)) AS first_admin_hr
  FROM cohort_diag cd
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON cd.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%exenatide%'
     OR LOWER(pr.drug) LIKE '%liraglutide%'
     OR LOWER(pr.drug) LIKE '%dulaglutide%'
     OR LOWER(pr.drug) LIKE '%semaglutide%'
     OR LOWER(pr.drug) LIKE '%lixisenatide%'
  GROUP BY cd.hadm_id
),
rates AS (
  SELECT
    COUNT(DISTINCT cd.hadm_id) AS cohort_size,
    COUNT(DISTINCT CASE WHEN ga.first_admin_hr IS NOT NULL AND ga.first_admin_hr <= 12 THEN cd.hadm_id END) AS first12h_count,
    COUNT(DISTINCT CASE WHEN ga.first_admin_hr IS NOT NULL AND ga.first_admin_hr <= 72 THEN cd.hadm_id END) AS final72h_count
  FROM cohort_diag cd
  LEFT JOIN glp1_admin ga
    ON cd.hadm_id = ga.hadm_id
)
SELECT
  cohort_size,
  ROUND(100.0 * first12h_count / cohort_size, 2) AS first12h_initiation_pct,
  ROUND(100.0 * final72h_count / cohort_size, 2) AS final72h_prevalence_pct,
  ROUND( (100.0 * final72h_count / cohort_size) - (100.0 * first12h_count / cohort_size), 2 ) AS net_pct_point_change
FROM rates;