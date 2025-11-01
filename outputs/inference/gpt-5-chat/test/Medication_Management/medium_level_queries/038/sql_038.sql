WITH cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  -- male 57-67
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 57 AND 67
),
dm_dx AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '250%')
     OR (icd_version = 10 AND icd_code LIKE 'E1[0-4]%')
),
ahf_dx AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code IN ('42821','42823','42831','42833'))
     OR (icd_version = 10 AND icd_code IN ('I5021','I5023','I5031','I5033','I50A1','I50A9'))
),
cohort_w_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN dm_dx dm ON c.hadm_id = dm.hadm_id
  JOIN ahf_dx hf ON c.hadm_id = hf.hadm_id
),
glp1_rx AS (
  SELECT DISTINCT p.subject_id, p.hadm_id, p.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE LOWER(p.drug) LIKE '%exenatide%'
     OR LOWER(p.drug) LIKE '%liraglutide%'
     OR LOWER(p.drug) LIKE '%dulaglutide%'
     OR LOWER(p.drug) LIKE '%semaglutide%'
     OR LOWER(p.drug) LIKE '%lixisenatide%'
     OR LOWER(p.drug) LIKE '%albiglutide%'
     OR LOWER(p.drug) LIKE '%tirzepatide%'
),
window_flags AS (
  SELECT
    cw.subject_id,
    cw.hadm_id,
    -- any GLP1 during admission
    CASE WHEN EXISTS (
      SELECT 1 FROM glp1_rx g
      WHERE g.hadm_id = cw.hadm_id
        AND g.starttime BETWEEN cw.admittime AND cw.dischtime
    ) THEN 1 ELSE 0 END AS any_glp1,
    -- GLP1 start in first 72h
    CASE WHEN EXISTS (
      SELECT 1 FROM glp1_rx g
      WHERE g.hadm_id = cw.hadm_id
        AND g.starttime >= cw.admittime
        AND g.starttime <= DATETIME_ADD(cw.admittime, INTERVAL 72 HOUR)
    ) THEN 1 ELSE 0 END AS glp1_first72h,
    -- GLP1 start in last 24h
    CASE WHEN EXISTS (
      SELECT 1 FROM glp1_rx g
      WHERE g.hadm_id = cw.hadm_id
        AND g.starttime >= DATETIME_SUB(cw.dischtime, INTERVAL 24 HOUR)
        AND g.starttime <= cw.dischtime
    ) THEN 1 ELSE 0 END AS glp1_last24h
  FROM cohort_w_dx cw
),
agg AS (
  SELECT
    COUNT(*) AS total_admissions,
    SUM(any_glp1) AS n_any_glp1,
    SUM(glp1_first72h) AS n_first72h,
    SUM(glp1_last24h) AS n_last24h
  FROM window_flags
)
SELECT
  total_admissions,
  n_any_glp1,
  ROUND(100.0 * n_any_glp1 / total_admissions, 2) AS prevalence_pct,
  ROUND(100.0 * n_first72h / total_admissions, 2) AS first72h_rate_pct,
  ROUND(100.0 * n_last24h / total_admissions, 2) AS last24h_rate_pct,
  ROUND( (100.0 * n_last24h / total_admissions) - (100.0 * n_first72h / total_admissions), 2) AS absolute_change_pctpts,
  ROUND( ((100.0 * n_last24h / total_admissions) - (100.0 * n_first72h / total_admissions))
         / NULLIF( (100.0 * n_first72h / total_admissions), 0), 2) AS relative_change
FROM agg;