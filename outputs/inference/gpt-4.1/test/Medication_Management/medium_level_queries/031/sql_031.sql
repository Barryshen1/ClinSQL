WITH cohort AS (
  -- Step 1: Find male inpatients age 53–63 with diabetes AND heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.hospital_expire_flag = 0 -- exclude in-hospital deaths
    AND EXISTS (
      -- Diabetes diagnosis
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250'))
          OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E0[89]|^E1[0-3]'))
        )
    )
    AND EXISTS (
      -- Heart failure diagnosis
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
          OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
        )
    )
),

glp1_prescriptions AS (
  -- Step 2: Find GLP-1 RA prescriptions (injectable only)
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.drug,
    pr.route
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE
    -- GLP-1 RA drug names (case-insensitive)
    LOWER(pr.drug) LIKE '%exenatide%'
    OR LOWER(pr.drug) LIKE '%liraglutide%'
    OR LOWER(pr.drug) LIKE '%dulaglutide%'
    OR LOWER(pr.drug) LIKE '%semaglutide%'
    OR LOWER(pr.drug) LIKE '%lixisenatide%'
    OR LOWER(pr.drug) LIKE '%albiglutide%'
    -- Injectable routes
    AND (
      LOWER(pr.route) LIKE '%sc%' -- subcutaneous
      OR LOWER(pr.route) LIKE '%subcut%'
      OR LOWER(pr.route) LIKE '%subcutaneous%'
      OR LOWER(pr.route) LIKE '%im%' -- intramuscular (rare, but possible)
      OR LOWER(pr.route) LIKE '%inject%'
    )
    AND pr.starttime IS NOT NULL
),

first_glp1_initiation AS (
  -- Step 3: For each admission, get first GLP-1 RA initiation time
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    MIN(gp.starttime) AS glp1_starttime
  FROM
    cohort c
    JOIN glp1_prescriptions gp
      ON c.subject_id = gp.subject_id
      AND c.hadm_id = gp.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime
),

window_flags AS (
  -- Step 4: Flag initiation window for each admission
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.glp1_starttime,
    CASE
      WHEN f.glp1_starttime BETWEEN f.admittime AND TIMESTAMP_ADD(f.admittime, INTERVAL 24 HOUR)
        THEN 'first_24h'
      WHEN f.glp1_starttime BETWEEN TIMESTAMP_SUB(f.dischtime, INTERVAL 12 HOUR) AND f.dischtime
        THEN 'final_12h'
      ELSE NULL
    END AS initiation_window
  FROM
    first_glp1_initiation f
)

-- Step 5: Calculate percentages
SELECT
  COUNT(DISTINCT c.hadm_id) AS total_admissions,
  COUNT(DISTINCT CASE WHEN w.initiation_window = 'first_24h' THEN w.hadm_id END) AS glp1_first_24h,
  COUNT(DISTINCT CASE WHEN w.initiation_window = 'final_12h' THEN w.hadm_id END) AS glp1_final_12h,
  ROUND(100 * COUNT(DISTINCT CASE WHEN w.initiation_window = 'first_24h' THEN w.hadm_id END) / COUNT(DISTINCT c.hadm_id), 2) AS pct_first_24h,
  ROUND(100 * COUNT(DISTINCT CASE WHEN w.initiation_window = 'final_12h' THEN w.hadm_id END) / COUNT(DISTINCT c.hadm_id), 2) AS pct_final_12h
FROM
  cohort c
  LEFT JOIN window_flags w
    ON c.hadm_id = w.hadm_id;