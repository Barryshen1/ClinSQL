WITH
-- 1. Base admissions for female patients aged 48–58
adms AS (
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
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.dischtime IS NOT NULL
),

-- 2. Identify admissions with both diabetes and heart failure
dx AS (
  SELECT
    di.hadm_id,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(d.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS has_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code
      AND di.icd_version = d.icd_version
  GROUP BY
    di.hadm_id
),

-- 3. Filter cohort to those admissions with both conditions
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    adms a
    JOIN dx
      ON a.hadm_id = dx.hadm_id
  WHERE
    dx.has_diabetes = 1
    AND dx.has_hf = 1
),

-- 4. Flag GLP-1 subcutaneous starts within time windows
glp_flags AS (
  SELECT
    c.hadm_id,
    MAX(CASE
          WHEN pr.starttime >= c.admittime
           AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
          THEN 1 ELSE 0
        END) AS first24_flag,
    MAX(CASE
          WHEN pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
           AND pr.starttime < c.dischtime
          THEN 1 ELSE 0
        END) AS final12_flag
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON c.hadm_id = pr.hadm_id
      AND LOWER(pr.route) LIKE '%sc%'
      AND LOWER(pr.drug) IN ('liraglutide', 'exenatide', 'dulaglutide', 'semaglutide')
  GROUP BY
    c.hadm_id
)

-- 5. Aggregate for prevalence
SELECT
  COUNT(*) AS total_admissions,
  SUM(first24_flag) AS starts_in_first_24h,
  ROUND(100.0 * SUM(first24_flag) / COUNT(*), 2) AS pct_first_24h,
  SUM(final12_flag) AS starts_in_final_12h,
  ROUND(100.0 * SUM(final12_flag) / COUNT(*), 2) AS pct_final_12h
FROM
  glp_flags;