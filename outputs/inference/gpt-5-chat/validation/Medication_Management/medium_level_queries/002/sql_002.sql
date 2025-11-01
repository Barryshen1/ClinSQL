WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- female, age 59–69
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    -- LOS ≥ 48h
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),
dx AS (
  SELECT DISTINCT hadm_id
  FROM (
    SELECT di.hadm_id,
           MAX(CASE 
                 WHEN di.icd_version = 9 AND di.icd_code LIKE '250%' 
                      AND (RIGHT(di.icd_code,1) IN ('0','2')) THEN 1
                 WHEN di.icd_version = 10 AND di.icd_code LIKE 'E11%' THEN 1
               END) OVER (PARTITION BY di.hadm_id) AS has_t2dm,
           MAX(CASE 
                 WHEN di.icd_version = 9 AND di.icd_code LIKE '428%' THEN 1
                 WHEN di.icd_version = 10 AND di.icd_code LIKE 'I50%' THEN 1
               END) OVER (PARTITION BY di.hadm_id) AS has_hf
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  )
  WHERE has_t2dm = 1 AND has_hf = 1
),
cohort_dx AS (
  SELECT c.*
  FROM cohort c
  JOIN dx
    ON c.hadm_id = dx.hadm_id
),
emar_with_route AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.emar_id,
    e.emar_seq,
    e.charttime,
    e.medication,
    LOWER(ed.route) AS route
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.subject_id = ed.subject_id
   AND e.emar_id = ed.emar_id
   AND e.emar_seq = ed.emar_seq
),
glp1_admin AS (
  SELECT
    er.subject_id,
    er.hadm_id,
    er.charttime
  FROM emar_with_route er
  JOIN cohort_dx c
    ON er.subject_id = c.subject_id
   AND er.hadm_id = c.hadm_id
  WHERE (
          LOWER(er.medication) LIKE '%liraglutide%' OR
          LOWER(er.medication) LIKE '%exenatide%' OR
          LOWER(er.medication) LIKE '%dulaglutide%' OR
          LOWER(er.medication) LIKE '%semaglutide%' OR
          LOWER(er.medication) LIKE '%lixisenatide%' OR
          LOWER(er.medication) LIKE '%albiglutide%'
        )
    AND (er.route LIKE '%subcut%' OR er.route LIKE '%injec%' OR er.route IS NULL)
),
use_flags AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN ga.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS used_early,
    MAX(CASE WHEN ga.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS used_late
  FROM cohort_dx c
  LEFT JOIN glp1_admin ga
    ON c.hadm_id = ga.hadm_id
  GROUP BY c.hadm_id
),
stats AS (
  SELECT
    COUNT(*) AS n_admissions,
    SUM(used_early) AS n_early,
    SUM(used_late) AS n_late
  FROM use_flags
)
SELECT
  n_admissions,
  n_early,
  ROUND(100 * n_early / n_admissions, 1) AS early_prevalence_pct,
  n_late,
  ROUND(100 * n_late / n_admissions, 1) AS late_prevalence_pct,
  ROUND( (100.0 * n_late / n_admissions) - (100.0 * n_early / n_admissions), 1) AS abs_pp_difference
FROM stats;