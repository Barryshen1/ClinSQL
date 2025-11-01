WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, p.anchor_age, p.gender, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 48 AND 58
    AND p.gender = 'F'
),
dx AS (
  SELECT c.subject_id, c.hadm_id,
         MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
                    OR (d.icd_version = 9 AND d.icd_code LIKE '250%') THEN 1 ELSE 0 END) AS has_t2dm,
         MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
                    OR (d.icd_version = 9 AND d.icd_code LIKE '428%') THEN 1 ELSE 0 END) AS has_hf
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN dx
    ON c.subject_id = dx.subject_id AND c.hadm_id = dx.hadm_id
  WHERE dx.has_t2dm = 1 AND dx.has_hf = 1
),
glp1_orders AS (
  SELECT pr.subject_id, pr.hadm_id, pr.starttime, pr.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE LOWER(pr.drug) LIKE '%exenatide%'
     OR LOWER(pr.drug) LIKE '%liraglutide%'
     OR LOWER(pr.drug) LIKE '%dulaglutide%'
     OR LOWER(pr.drug) LIKE '%semaglutide%'
     OR LOWER(pr.drug) LIKE '%byetta%'
     OR LOWER(pr.drug) LIKE '%victoza%'
     OR LOWER(pr.drug) LIKE '%trulicity%'
     OR LOWER(pr.drug) LIKE '%ozempic%'
),
initiations AS (
  SELECT c.subject_id, c.hadm_id,
         MAX(CASE WHEN g.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
                  THEN 1 ELSE 0 END) AS init_first72h,
         MAX(CASE WHEN g.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
                  THEN 1 ELSE 0 END) AS init_last48h
  FROM cohort_with_dx c
  LEFT JOIN glp1_orders g
    ON c.subject_id = g.subject_id AND c.hadm_id = g.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),
stats AS (
  SELECT
    COUNT(*) AS total_admissions,
    SUM(init_first72h) AS first72h_inits,
    SUM(init_last48h) AS last48h_inits
  FROM initiations
)
SELECT
  total_admissions,
  first72h_inits,
  last48h_inits,
  SAFE_DIVIDE(first72h_inits, total_admissions) * 100 AS first72h_pct,
  SAFE_DIVIDE(last48h_inits, total_admissions) * 100 AS last48h_pct,
  (SAFE_DIVIDE(first72h_inits, total_admissions) - SAFE_DIVIDE(last48h_inits, total_admissions)) * 100 AS abs_diff_pp
FROM stats;