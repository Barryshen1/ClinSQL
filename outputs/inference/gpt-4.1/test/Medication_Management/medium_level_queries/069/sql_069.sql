WITH cohort AS (
  -- Select males aged 48-58 at admission
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 24
),
dx_diabetes AS (
  -- Admissions with type 2 diabetes
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (
      -- ICD-10 E11.*
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E11'))
      -- ICD-9 250.x0, 250.x2 (type 2 DM)
      OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250[.]([0-9]{1,2})[02]$'))
    )
),
dx_hf AS (
  -- Admissions with heart failure
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (
      -- ICD-10 I50.*
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
      -- ICD-9 428.*
      OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
    )
),
cohort_dx AS (
  -- Cohort with both diagnoses
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime
  FROM cohort c
  INNER JOIN dx_diabetes d1 ON c.hadm_id = d1.hadm_id
  INNER JOIN dx_hf d2 ON c.hadm_id = d2.hadm_id
),
glp1_rx AS (
  -- GLP-1 RA prescriptions/administrations
  SELECT
    hadm_id,
    starttime,
    stoptime,
    LOWER(drug) AS drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%exenatide%'
    OR LOWER(drug) LIKE '%liraglutide%'
    OR LOWER(drug) LIKE '%dulaglutide%'
    OR LOWER(drug) LIKE '%semaglutide%'
    OR LOWER(drug) LIKE '%lixisenatide%'
    OR LOWER(drug) LIKE '%albiglutide%'
),
glp1_pharm AS (
  -- GLP-1 RA from pharmacy table (sometimes more complete)
  SELECT
    hadm_id,
    starttime,
    stoptime,
    LOWER(medication) AS drug
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE
    LOWER(medication) LIKE '%exenatide%'
    OR LOWER(medication) LIKE '%liraglutide%'
    OR LOWER(medication) LIKE '%dulaglutide%'
    OR LOWER(medication) LIKE '%semaglutide%'
    OR LOWER(medication) LIKE '%lixisenatide%'
    OR LOWER(medication) LIKE '%albiglutide%'
),
glp1_all AS (
  -- Union all GLP-1 RA exposures
  SELECT hadm_id, starttime, stoptime, drug FROM glp1_rx
  UNION ALL
  SELECT hadm_id, starttime, stoptime, drug FROM glp1_pharm
),
exposure AS (
  -- For each admission, flag exposure in first 12h and final 12h
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- First 12h window
    MAX(
      CASE
        WHEN
          g.starttime >= c.admittime
          AND g.starttime < DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
        THEN 1 ELSE 0 END
    ) AS glp1_first12h,
    -- Final 12h window
    MAX(
      CASE
        WHEN
          g.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
          AND g.starttime < c.dischtime
        THEN 1 ELSE 0 END
    ) AS glp1_final12h
  FROM cohort_dx c
  LEFT JOIN glp1_all g
    ON c.hadm_id = g.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime
),
summary AS (
  SELECT
    COUNT(*) AS cohort_size,
    SUM(glp1_first12h) AS n_first12h,
    SUM(glp1_final12h) AS n_final12h,
    SAFE_DIVIDE(SUM(glp1_first12h), COUNT(*)) * 100 AS pct_first12h,
    SAFE_DIVIDE(SUM(glp1_final12h), COUNT(*)) * 100 AS pct_final12h,
    SAFE_DIVIDE(SUM(glp1_final12h), COUNT(*)) * 100
      - SAFE_DIVIDE(SUM(glp1_first12h), COUNT(*)) * 100 AS net_change_pct
  FROM exposure
)
SELECT
  cohort_size,
  n_first12h,
  pct_first12h,
  n_final12h,
  pct_final12h,
  net_change_pct
FROM summary;