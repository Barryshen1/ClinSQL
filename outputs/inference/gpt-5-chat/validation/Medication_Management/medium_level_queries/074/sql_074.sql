WITH cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  -- Female aged 48–58
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),
dx AS (
  SELECT hadm_id,
         MAX(CASE WHEN 
           (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%'))
           OR (d.icd_version = 9 AND d.icd_code LIKE '250%')
         THEN 1 ELSE 0 END) AS has_diabetes,
         MAX(CASE WHEN 
           (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
           OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
         THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY hadm_id
),
cohort_with_conditions AS (
  SELECT c.*
  FROM cohort c
  JOIN dx
    ON c.hadm_id = dx.hadm_id
  WHERE dx.has_diabetes = 1
    AND dx.has_hf = 1
),
glp1_admin AS (
  SELECT e.subject_id, e.hadm_id, MIN(e.charttime) AS first_glp1_time
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.subject_id = ed.subject_id AND e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  WHERE LOWER(e.medication) LIKE '%liraglutide%'
     OR LOWER(e.medication) LIKE '%semaglutide%'
     OR LOWER(e.medication) LIKE '%dulaglutide%'
     OR LOWER(e.medication) LIKE '%exenatide%'
     OR LOWER(e.medication) LIKE '%albiglutide%'
  AND LOWER(ed.route) LIKE '%subcutaneous%'
  GROUP BY e.subject_id, e.hadm_id
),
combined AS (
  SELECT coh.*, ga.first_glp1_time
  FROM cohort_with_conditions coh
  LEFT JOIN glp1_admin ga
    ON coh.subject_id = ga.subject_id AND coh.hadm_id = ga.hadm_id
  WHERE coh.admittime IS NOT NULL AND coh.dischtime IS NOT NULL
)
SELECT
  COUNT(*) AS cohort_size,
  SUM(CASE WHEN first_glp1_time IS NOT NULL 
              AND first_glp1_time <= DATETIME_ADD(admittime, INTERVAL 24 HOUR)
           THEN 1 ELSE 0 END) AS first_24h_count,
  SAFE_DIVIDE(SUM(CASE WHEN first_glp1_time IS NOT NULL 
              AND first_glp1_time <= DATETIME_ADD(admittime, INTERVAL 24 HOUR)
           THEN 1 ELSE 0 END), COUNT(*)) * 100 AS first_24h_pct,
  SUM(CASE WHEN first_glp1_time IS NOT NULL
              AND first_glp1_time >= DATETIME_SUB(dischtime, INTERVAL 12 HOUR)
           THEN 1 ELSE 0 END) AS final_12h_count,
  SAFE_DIVIDE(SUM(CASE WHEN first_glp1_time IS NOT NULL
              AND first_glp1_time >= DATETIME_SUB(dischtime, INTERVAL 12 HOUR)
           THEN 1 ELSE 0 END), COUNT(*)) * 100 AS final_12h_pct
FROM combined;