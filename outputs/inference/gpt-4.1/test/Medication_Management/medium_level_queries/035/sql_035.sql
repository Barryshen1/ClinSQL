WITH
-- 1. Select female inpatients aged 57-67 at admission
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48 -- ensure stay is at least 48h
),

-- 2. Find admissions with diabetes and heart failure diagnoses
dx_diabetes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    -- ICD-10 E08-E13 or ICD-9 250
    ( (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E0[8-9]|^E1[0-3]'))
      OR (d.icd_version = 9 AND d.icd_code LIKE '250%') )
),
dx_hf AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    -- ICD-10 I50 or ICD-9 428
    ( (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
      OR (d.icd_version = 9 AND d.icd_code LIKE '428%') )
),
cohort_dx AS (
  SELECT c.*
  FROM cohort c
    JOIN dx_diabetes d1 ON c.hadm_id = d1.hadm_id
    JOIN dx_hf d2 ON c.hadm_id = d2.hadm_id
),

-- 3. Identify GLP-1 RA prescriptions in each window
glp1_drugs AS (
  -- List of GLP-1 RA drugs (expand as needed)
  SELECT 'exenatide' AS drug UNION ALL
  SELECT 'liraglutide' UNION ALL
  SELECT 'dulaglutide' UNION ALL
  SELECT 'semaglutide' UNION ALL
  SELECT 'albiglutide' UNION ALL
  SELECT 'lixisenatide'
),
presc_glp1 AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN glp1_drugs g
      ON LOWER(pr.drug) LIKE CONCAT('%', LOWER(g.drug), '%')
  WHERE
    pr.starttime IS NOT NULL
),

-- 4. For each admission, flag if GLP-1 RA prescribed in first 48h or final 12h
window_flags AS (
  SELECT
    cd.subject_id,
    cd.hadm_id,
    cd.admittime,
    cd.dischtime,
    -- First 48h window
    CASE WHEN EXISTS (
      SELECT 1 FROM presc_glp1 p
      WHERE p.hadm_id = cd.hadm_id
        AND p.starttime BETWEEN cd.admittime AND TIMESTAMP_ADD(cd.admittime, INTERVAL 48 HOUR)
    ) THEN 1 ELSE 0 END AS glp1_first48h,
    -- Final 12h window
    CASE WHEN EXISTS (
      SELECT 1 FROM presc_glp1 p
      WHERE p.hadm_id = cd.hadm_id
        AND p.starttime BETWEEN TIMESTAMP_SUB(cd.dischtime, INTERVAL 12 HOUR) AND cd.dischtime
    ) THEN 1 ELSE 0 END AS glp1_final12h
  FROM
    cohort_dx cd
)

-- 5. Aggregate and calculate prevalence, absolute and relative change
SELECT
  COUNT(*) AS n_admissions,
  ROUND(SUM(glp1_first48h) / COUNT(*) * 100, 2) AS prevalence_first48h_pct,
  ROUND(SUM(glp1_final12h) / COUNT(*) * 100, 2) AS prevalence_final12h_pct,
  ROUND(SUM(glp1_final12h) / COUNT(*) * 100 - SUM(glp1_first48h) / COUNT(*) * 100, 2) AS absolute_change_pct,
  ROUND(
    CASE
      WHEN SUM(glp1_first48h) = 0 THEN NULL
      ELSE (SUM(glp1_final12h) / COUNT(*) * 100 - SUM(glp1_first48h) / COUNT(*) * 100) / (SUM(glp1_first48h) / COUNT(*) * 100)
    END
  , 3) AS relative_change
FROM window_flags;