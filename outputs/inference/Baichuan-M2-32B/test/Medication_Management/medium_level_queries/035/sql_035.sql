WITH patients_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- Compute birth date using patients table's anchor_year and anchor_age
    DATE_SUB(CAST(CONCAT(CAST(p.anchor_year AS STRING), '-01-01') AS DATE), INTERVAL p.anchor_age YEAR) AS birth_date,
    -- Compute age at admission in years
    TIMESTAMP_DIFF(a.admittime, birth_date, YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.admittime, birth_date, YEAR) BETWEEN 57 AND 67
),
admissions_with_conditions AS (
  SELECT 
    a.hadm_id
  FROM patients_admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 
    ON a.hadm_id = d1.hadm_id
    AND d1.icd_version = 10
    AND d1.icd_code IN (
      SELECT icd_code 
      FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
      WHERE icd_version = 10 
        AND long_title LIKE '%diabetes%'
    )
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 
    ON a.hadm_id = d2.hadm_id
    AND d2.icd_version = 10
    AND d2.icd_code IN (
      SELECT icd_code 
      FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
      WHERE icd_version = 10 
        AND long_title LIKE '%heart failure%'
    )
),
prescriptions_glp1 AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    -- Use backticks for the alias `window` to avoid reserved keyword error
    CASE 
      WHEN p.starttime BETWEEN a.admittime AND LEAST(DATETIME_ADD(a.admittime, INTERVAL 48 HOUR), a.dischtime) 
        THEN 'first48h'
      WHEN p.starttime BETWEEN GREATEST(a.admittime, DATETIME_SUB(a.dischtime, INTERVAL 12 HOUR)) AND a.dischtime 
        THEN 'final12h'
      ELSE NULL 
    END AS `window`
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN admissions_with_conditions a 
    ON p.hadm_id = a.hadm_id
  WHERE LOWER(p.drug) LIKE '%glp-1%' 
     OR p.drug IN ('semaglutide', 'liraglutide', 'dulaglutide', 'exenatide', 'lixisenatide', 'albiglutide', 'tirzepatide')
),
admission_windows AS (
  SELECT 
    a.hadm_id,
    MAX(CASE WHEN pg.`window` = 'first48h' THEN 1 ELSE 0 END) AS has_glp1_first48h,
    MAX(CASE WHEN pg.`window` = 'final12h' THEN 1 ELSE 0 END) AS has_glp1_final12h
  FROM admissions_with_conditions a
  LEFT JOIN prescriptions_glp1 pg 
    ON a.hadm_id = pg.hadm_id
  GROUP BY a.hadm_id
)
SELECT 
  COUNT(*) AS total_admissions,
  SUM(has_glp1_first48h) AS count_first48h,
  SUM(has_glp1_final12h) AS count_final12h,
  (SUM(has_glp1_first48h) * 100.0 / COUNT(*)) AS prevalence_first48h,
  (SUM(has_glp1_final12h) * 100.0 / COUNT(*)) AS prevalence_final12h,
  (SUM(has_glp1_final12h) - SUM(has_glp1_first48h)) AS absolute_change,
  ((SUM(has_glp1_final12h) - SUM(has_glp1_first48h)) * 100.0 / NULLIF(SUM(has_glp1_first48h), 0)) AS relative_change
FROM admission_windows;