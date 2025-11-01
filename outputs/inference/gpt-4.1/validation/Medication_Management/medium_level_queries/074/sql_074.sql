WITH cohort AS (
  -- Select female inpatients age 48-58 with diabetes AND heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- Diabetes ICD-10 E08-E13 or ICD-9 250.*
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E0[8-9]|^E1[0-3]'))
          OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- Heart Failure ICD-10 I50.* or ICD-9 428.*
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
          OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
        )
    )
),
glp1_presc AS (
  -- Find GLP-1 subcutaneous starts in prescriptions
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.drug,
    pr.route
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions pr
  WHERE LOWER(pr.drug) LIKE '%exenatide%'
     OR LOWER(pr.drug) LIKE '%liraglutide%'
     OR LOWER(pr.drug) LIKE '%dulaglutide%'
     OR LOWER(pr.drug) LIKE '%semaglutide%'
     OR LOWER(pr.drug) LIKE '%lixisenatide%'
),
glp1_subcut AS (
  -- Only subcutaneous starts
  SELECT
    g.subject_id,
    g.hadm_id,
    g.starttime
  FROM glp1_presc g
  WHERE LOWER(g.route) LIKE '%subcut%'
),
first24h AS (
  -- Admissions with GLP-1 subcut start in first 24h
  SELECT DISTINCT
    c.hadm_id
  FROM cohort c
  JOIN glp1_subcut g
    ON c.hadm_id = g.hadm_id
  WHERE g.starttime >= c.admittime
    AND g.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),
final12h AS (
  -- Admissions with GLP-1 subcut start in final 12h
  SELECT DISTINCT
    c.hadm_id
  FROM cohort c
  JOIN glp1_subcut g
    ON c.hadm_id = g.hadm_id
  WHERE g.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
    AND g.starttime < c.dischtime
)
SELECT
  COUNT(DISTINCT cohort.hadm_id) AS total_admissions,
  COUNT(DISTINCT first24h.hadm_id) AS first24h_glp1_starts,
  COUNT(DISTINCT final12h.hadm_id) AS final12h_glp1_starts,
  ROUND(COUNT(DISTINCT first24h.hadm_id) * 100.0 / COUNT(DISTINCT cohort.hadm_id), 2) AS first24h_prevalence_pct,
  ROUND(COUNT(DISTINCT final12h.hadm_id) * 100.0 / COUNT(DISTINCT cohort.hadm_id), 2) AS final12h_prevalence_pct
FROM cohort
LEFT JOIN first24h ON cohort.hadm_id = first24h.hadm_id
LEFT JOIN final12h ON cohort.hadm_id = final12h.hadm_id;