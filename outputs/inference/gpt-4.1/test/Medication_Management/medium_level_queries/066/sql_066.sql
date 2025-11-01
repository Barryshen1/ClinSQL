WITH cohort AS (
  -- Step 1: Identify male inpatients age 58-68 with T2DM and heart failure, admissions >=72h
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- Age filter
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 58 AND 68
      AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
      AND a.admittime IS NOT NULL
      AND a.dischtime IS NOT NULL
      AND a.hadm_id IS NOT NULL
      AND a.subject_id IS NOT NULL
      -- Must have T2DM and heart failure diagnoses
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND (
            -- T2DM ICD-10 E11.*, ICD-9 250.0x, 250.2x
            (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E11'))
            OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250[.]0|^250[.]2'))
          )
      )
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND (
            -- Heart failure ICD-10 I50.*, ICD-9 428.*
            (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
            OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
          )
      )
),

glp1_prescriptions AS (
  -- Step 2: Find GLP-1 agonist prescriptions per admission
  SELECT
    pr.subject_id,
    pr.hadm_id,
    MIN(pr.starttime) AS first_glp1_starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE
    -- GLP-1 agonist drug names (case-insensitive)
    LOWER(pr.drug) LIKE '%exenatide%'
    OR LOWER(pr.drug) LIKE '%liraglutide%'
    OR LOWER(pr.drug) LIKE '%dulaglutide%'
    OR LOWER(pr.drug) LIKE '%semaglutide%'
    OR LOWER(pr.drug) LIKE '%albiglutide%'
    OR LOWER(pr.drug) LIKE '%lixisenatide%'
  GROUP BY
    pr.subject_id, pr.hadm_id
),

window_flags AS (
  -- Step 3: For each cohort admission, flag GLP-1 initiation in first 72h and/or final 12h
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    gp.first_glp1_starttime,
    -- First 72h window
    CASE
      WHEN gp.first_glp1_starttime IS NOT NULL
        AND gp.first_glp1_starttime >= c.admittime
        AND gp.first_glp1_starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
      THEN 1 ELSE 0 END AS started_first_72h,
    -- Final 12h window
    CASE
      WHEN gp.first_glp1_starttime IS NOT NULL
        AND gp.first_glp1_starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
        AND gp.first_glp1_starttime < c.dischtime
      THEN 1 ELSE 0 END AS started_final_12h
  FROM
    cohort c
    LEFT JOIN glp1_prescriptions gp
      ON c.subject_id = gp.subject_id AND c.hadm_id = gp.hadm_id
)

SELECT
  COUNT(*) AS n_admissions,
  SUM(started_first_72h) AS n_started_first_72h,
  SUM(started_final_12h) AS n_started_final_12h,
  SAFE_DIVIDE(SUM(started_first_72h), COUNT(*)) * 100 AS pct_started_first_72h,
  SAFE_DIVIDE(SUM(started_final_12h), COUNT(*)) * 100 AS pct_started_final_12h,
  SAFE_DIVIDE(SUM(started_first_72h), COUNT(*)) * 100
    - SAFE_DIVIDE(SUM(started_final_12h), COUNT(*)) * 100 AS absolute_difference_pp
FROM
  window_flags;