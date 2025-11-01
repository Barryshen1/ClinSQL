WITH cohort_admissions AS (
  -- Step 1: select male patients aged 48–58 with both T2DM and heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON a.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
      ON dx.icd_code = dxd.icd_code
      AND dx.icd_version = dxd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime
  HAVING
    -- must have at least one diabetes type 2 diagnosis
    COUNTIF(LOWER(dxd.long_title) LIKE '%type 2 diabetes%') > 0
    -- and at least one heart failure diagnosis
    AND COUNTIF(LOWER(dxd.long_title) LIKE '%heart failure%') > 0
),
glp1_flags AS (
  -- Step 2: flag GLP-1 receipt in first 12h and final 12h
  SELECT
    ca.subject_id,
    ca.hadm_id,
    -- first 12h window
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        WHERE pr.hadm_id = ca.hadm_id
          AND pr.starttime BETWEEN ca.admittime AND ca.admittime + INTERVAL 12 HOUR
          AND LOWER(pr.drug) LIKE '%exenatide%'
          OR LOWER(pr.drug) LIKE '%liraglutide%'
          OR LOWER(pr.drug) LIKE '%dulaglutide%'
          OR LOWER(pr.drug) LIKE '%semaglutide%'
      ) THEN 1 ELSE 0 END AS first12h,
    -- last 12h window
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        WHERE pr.hadm_id = ca.hadm_id
          AND pr.starttime BETWEEN ca.dischtime - INTERVAL 12 HOUR AND ca.dischtime
          AND LOWER(pr.drug) LIKE '%exenatide%'
          OR LOWER(pr.drug) LIKE '%liraglutide%'
          OR LOWER(pr.drug) LIKE '%dulaglutide%'
          OR LOWER(pr.drug) LIKE '%semaglutide%'
      ) THEN 1 ELSE 0 END AS last12h
  FROM
    cohort_admissions ca
)
-- Step 3: aggregate percentages and net change
SELECT
  COUNT(*) AS total_admissions,
  SUM(first12h) AS n_first12h,
  ROUND(100.0 * SUM(first12h) / COUNT(*), 2) AS pct_first12h,
  SUM(last12h) AS n_last12h,
  ROUND(100.0 * SUM(last12h) / COUNT(*), 2) AS pct_last12h,
  ROUND(
    100.0 * SUM(last12h) / COUNT(*) 
    - 100.0 * SUM(first12h) / COUNT(*),
    2
  ) AS pct_net_change
FROM
  glp1_flags;