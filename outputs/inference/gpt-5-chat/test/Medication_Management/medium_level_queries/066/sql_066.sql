WITH
-- Identify admissions with T2DM and HF
dx_flags AS (
  SELECT
    hadm_id,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code LIKE '250%' AND RIGHT(icd_code,1) IN ('0','2'))
        OR (icd_version = 10 AND icd_code LIKE 'E11%')
      THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code LIKE '428%')
        OR (icd_version = 10 AND icd_code LIKE 'I50%')
      THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

-- GLP-1 agonist prescriptions per admission & time
glp1_rx AS (
  SELECT
    hadm_id,
    MIN(starttime) AS first_start
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%liraglutide%'
    OR LOWER(drug) LIKE '%semaglutide%'
    OR LOWER(drug) LIKE '%exenatide%'
    OR LOWER(drug) LIKE '%dulaglutide%'
    OR LOWER(drug) LIKE '%albiglutide%'
    OR LOWER(drug) LIKE '%lixisenatide%'
  GROUP BY hadm_id
),

-- Join to admissions & patients, apply inclusion criteria
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN dx_flags dx
    ON a.hadm_id = dx.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND dx.has_t2dm = 1
    AND dx.has_hf = 1
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),

-- Flags for start in first 72h or last 12h
flags AS (
  SELECT
    c.*,
    CASE
      WHEN rx.hadm_id IS NOT NULL
       AND rx.first_start >= c.admittime
       AND rx.first_start < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
      THEN 1 ELSE 0 END AS first72h_flag,
    CASE
      WHEN rx.hadm_id IS NOT NULL
       AND rx.first_start >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
       AND rx.first_start <= c.dischtime
      THEN 1 ELSE 0 END AS last12h_flag
  FROM cohort c
  LEFT JOIN glp1_rx rx
    ON c.hadm_id = rx.hadm_id
)

SELECT
  COUNT(*) AS n_admissions,
  ROUND(100 * AVG(first72h_flag), 1) AS pct_first72h,
  ROUND(100 * AVG(last12h_flag), 1) AS pct_last12h,
  ROUND(100 * (AVG(first72h_flag) - AVG(last12h_flag)), 1) AS abs_diff_pp
FROM flags;