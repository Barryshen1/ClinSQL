WITH
-- Get relevant admissions for women aged 75-85 with diabetes and acute heart failure
relevant_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS admission_duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
  ON
    a.hadm_id = d1.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag1
  ON
    d1.icd_code = diag1.icd_code AND d1.icd_version = diag1.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
  ON
    a.hadm_id = d2.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag2
  ON
    d2.icd_code = diag2.icd_code AND d2.icd_version = diag2.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 36
    AND (
      -- Diabetes ICD codes (E11-E14)
      (diag1.icd_code LIKE 'E11%' OR diag1.icd_code LIKE 'E12%' OR diag1.icd_code LIKE 'E13%' OR diag1.icd_code LIKE 'E14%')
      -- Acute heart failure ICD codes (I50.9, I50.1, etc.)
      AND (diag2.icd_code LIKE 'I50%')
    )
),

-- Identify GLP-1 medications (injectable)
glp1_medications AS (
  SELECT DISTINCT
    subject_id,
    hadm_id,
    starttime,
    drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%exenatide%'
    OR LOWER(drug) LIKE '%liraglutide%'
    OR LOWER(drug) LIKE '%dulaglutide%'
    OR LOWER(drug) LIKE '%semaglutide%'
    OR LOWER(drug) LIKE '%lixisenatide%'
    OR LOWER(drug) LIKE '%albiglutide%'
),

-- Calculate timing of GLP-1 administration
glp1_timing AS (
  SELECT
    ra.hadm_id,
    ra.admittime,
    ra.dischtime,
    CASE
      WHEN TIMESTAMP_DIFF(gm.starttime, ra.admittime, HOUR) <= 24 THEN 1
      ELSE 0
    END AS started_in_first_24h,
    CASE
      WHEN TIMESTAMP_DIFF(ra.dischtime, gm.starttime, HOUR) <= 12 THEN 1
      ELSE 0
    END AS started_in_final_12h
  FROM
    relevant_admissions ra
  LEFT JOIN
    glp1_medications gm
  ON
    ra.hadm_id = gm.hadm_id
)

-- Calculate percentages
SELECT
  ROUND(100 * SUM(started_in_first_24h) / COUNT(hadm_id), 2) AS percent_first_24h,
  ROUND(100 * SUM(started_in_final_12h) / COUNT(hadm_id), 2) AS percent_final_12h
FROM
  glp1_timing;