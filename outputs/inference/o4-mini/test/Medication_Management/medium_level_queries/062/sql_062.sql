WITH cohort AS (
  -- Female inpatients age 50-60 with diabetes AND heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND EXISTS (
      -- Diabetes diagnosis
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      -- Heart failure diagnosis
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
glp1_inits AS (
  -- First GLP-1 prescription per admission
  SELECT
    c.hadm_id,
    MIN(p.starttime) AS first_glp1_time,
    c.admittime,
    c.dischtime
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE
    UPPER(p.drug) IN (
      'EXENATIDE',
      'LIRAGLUTIDE',
      'DULAGLUTIDE',
      'SEMAGLUTIDE',
      'ALBIGLUTIDE',
      'LIXISENATIDE'
    )
  GROUP BY
    c.hadm_id,
    c.admittime,
    c.dischtime
),
flagged AS (
  SELECT
    hadm_id,
    -- Flag if first GLP-1 is within first 72 h
    CASE
      WHEN TIMESTAMP_DIFF(first_glp1_time, admittime, HOUR) BETWEEN 0 AND 72 THEN 1
      ELSE 0
    END AS first72_flag,
    -- Flag if first GLP-1 is within final 72 h
    CASE
      WHEN TIMESTAMP_DIFF(dischtime, first_glp1_time, HOUR) BETWEEN 0 AND 72 THEN 1
      ELSE 0
    END AS last72_flag
  FROM glp1_inits
)
SELECT
  COUNT(DISTINCT c.hadm_id) AS total_admissions,
  SUM(f.first72_flag) AS n_first72,
  SUM(f.last72_flag) AS n_last72,
  ROUND(SAFE_DIVIDE(SUM(f.first72_flag), COUNT(DISTINCT c.hadm_id)) * 100, 2) AS pct_first72,
  ROUND(SAFE_DIVIDE(SUM(f.last72_flag), COUNT(DISTINCT c.hadm_id)) * 100, 2) AS pct_last72,
  ROUND(
    SAFE_DIVIDE(SUM(f.last72_flag), COUNT(DISTINCT c.hadm_id))
    - SAFE_DIVIDE(SUM(f.first72_flag), COUNT(DISTINCT c.hadm_id))
    , 4
  ) AS absolute_change,
  ROUND(
    SAFE_DIVIDE(
      SAFE_DIVIDE(SUM(f.last72_flag), COUNT(DISTINCT c.hadm_id))
      - SAFE_DIVIDE(SUM(f.first72_flag), COUNT(DISTINCT c.hadm_id)),
      SAFE_DIVIDE(SUM(f.first72_flag), COUNT(DISTINCT c.hadm_id))
    )
    , 4
  ) AS relative_change
FROM
  cohort c
  LEFT JOIN flagged f
    ON c.hadm_id = f.hadm_id;