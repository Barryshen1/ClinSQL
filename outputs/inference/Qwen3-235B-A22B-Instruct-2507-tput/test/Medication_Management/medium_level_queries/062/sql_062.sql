WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Compute age at admission
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 50 AND 60
),

diabetes_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%diabetes%'
    AND icd_version = 10
    -- Broaden: include all diabetes types
    AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%')
),

heart_failure_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%heart failure%'
    AND icd_version = 10
    AND icd_code LIKE 'I50%'
),

admissions_with_conditions AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diab
    ON pa.hadm_id = diab.hadm_id
  INNER JOIN diabetes_codes dc
    ON diab.icd_code = dc.icd_code
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd hf
    ON pa.hadm_id = hf.hadm_id
  INNER JOIN heart_failure_codes hfc
    ON hf.icd_code = hfc.icd_code
  GROUP BY pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime
),

glp1_drugs AS (
  SELECT DISTINCT
    hadm_id,
    starttime,
    drug,
    route
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
  WHERE LOWER(drug) IN ('liraglutide', 'dulaglutide', 'semaglutide', 'exenatide')
    AND LOWER(route) LIKE '%subcut%'
    AND starttime IS NOT NULL
),

initiation_windows AS (
  SELECT
    awc.hadm_id,
    awc.admittime,
    awc.dischtime,
    -- Flag if GLP-1 started in first 72h
    MAX(CASE
      WHEN g.starttime >= awc.admittime AND g.starttime <= awc.admittime + INTERVAL '72' HOUR
      THEN 1 ELSE 0 END) AS initiated_first_72h,
    -- Flag if GLP-1 started in final 72h
    MAX(CASE
      WHEN g.starttime >= awc.dischtime - INTERVAL '72' HOUR AND g.starttime <= awc.dischtime
      THEN 1 ELSE 0 END) AS initiated_final_72h
  FROM admissions_with_conditions awc
  LEFT JOIN glp1_drugs g
    ON awc.hadm_id = g.hadm_id
  GROUP BY awc.hadm_id, awc.admittime, awc.dischtime
),

summary_stats AS (
  SELECT
    COUNT(*) AS total_admissions,
    SUM(initiated_first_72h) AS first_72h_count,
    SUM(initiated_final_72h) AS final_72h_count
  FROM initiation_windows
)

SELECT
  total_admissions,
  first_72h_count,
  final_72h_count,
  ROUND(100.0 * first_72h_count / total_admissions, 2) AS first_72h_rate_pct,
  ROUND(100.0 * final_72h_count / total_admissions, 2) AS final_72h_rate_pct,
  ROUND(100.0 * final_72h_count / total_admissions - 100.0 * first_72h_count / total_admissions, 2) AS absolute_change_pct,
  CASE
    WHEN first_72h_count = 0 THEN NULL
    ELSE ROUND(
      (100.0 * final_72h_count / total_admissions - 100.0 * first_72h_count / total_admissions) / (100.0 * first_72h_count / total_admissions) * 100, 2)
  END AS relative_change_pct
FROM summary_stats;