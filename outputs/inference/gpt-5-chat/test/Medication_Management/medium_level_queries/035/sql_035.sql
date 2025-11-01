WITH cohort AS (
  -- Base female inpatients age 57-67
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
),
dx_flags AS (
  -- Flag diabetes and heart failure per admission
  SELECT d.subject_id, d.hadm_id,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%')
            OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%'))
          THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND d.icd_code LIKE '428%')
            OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.subject_id, d.hadm_id
),
cohort_with_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN dx_flags f
    ON c.subject_id = f.subject_id AND c.hadm_id = f.hadm_id
  WHERE f.has_diabetes = 1 AND f.has_hf = 1
),
glp1_rx AS (
  SELECT DISTINCT hadm_id,
    CASE 
      WHEN LOWER(drug) LIKE '%exenatide%' THEN 1
      WHEN LOWER(drug) LIKE '%liraglutide%' THEN 1
      WHEN LOWER(drug) LIKE '%dulaglutide%' THEN 1
      WHEN LOWER(drug) LIKE '%semaglutide%' THEN 1
      WHEN LOWER(drug) LIKE '%lixisenatide%' THEN 1
      WHEN LOWER(drug) LIKE '%albiglutide%' THEN 1
    ELSE 0 END AS is_glp1,
    starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%exenatide%'
     OR LOWER(drug) LIKE '%liraglutide%'
     OR LOWER(drug) LIKE '%dulaglutide%'
     OR LOWER(drug) LIKE '%semaglutide%'
     OR LOWER(drug) LIKE '%lixisenatide%'
     OR LOWER(drug) LIKE '%albiglutide%'
),
window_flags AS (
  SELECT c.hadm_id,
    MAX(CASE WHEN r.is_glp1 = 1 
              AND r.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS glp1_first48h,
    MAX(CASE WHEN r.is_glp1 = 1 
              AND r.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
             THEN 1 ELSE 0 END) AS glp1_last12h
  FROM cohort_with_dx c
  LEFT JOIN glp1_rx r
    ON c.hadm_id = r.hadm_id
  GROUP BY c.hadm_id
),
prevalence AS (
  SELECT 
    COUNT(*) AS n_admissions,
    SUM(glp1_first48h) AS cnt_first48h,
    SUM(glp1_last12h) AS cnt_last12h
  FROM window_flags
)
SELECT
  n_admissions,
  cnt_first48h,
  SAFE_DIVIDE(cnt_first48h, n_admissions) * 100 AS prev_first48h_pct,
  cnt_last12h,
  SAFE_DIVIDE(cnt_last12h, n_admissions) * 100 AS prev_last12h_pct,
  (SAFE_DIVIDE(cnt_last12h, n_admissions) * 100) - (SAFE_DIVIDE(cnt_first48h, n_admissions) * 100) AS absolute_change_pct,
  SAFE_DIVIDE(
    ((SAFE_DIVIDE(cnt_last12h, n_admissions) * 100) - (SAFE_DIVIDE(cnt_first48h, n_admissions) * 100)),
    (SAFE_DIVIDE(cnt_first48h, n_admissions) * 100)
  ) AS relative_change
FROM prevalence;