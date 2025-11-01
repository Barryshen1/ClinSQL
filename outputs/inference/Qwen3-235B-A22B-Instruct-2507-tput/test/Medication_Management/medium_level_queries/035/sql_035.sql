WITH diabetes_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%diabetes%'
    AND (icd_version = 10 OR icd_version = 9)
    AND (
      (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'E11') OR
      (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'E10') OR
      (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250')
    )
),
hf_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (LOWER(long_title) LIKE '%heart failure%'
    OR LOWER(long_title) LIKE '%cardiomyopathy%'
    OR LOWER(long_title) LIKE '%congestive heart failure%')
    AND (icd_version = 10 OR icd_version = 9)
    AND (
      (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50') OR
      (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428')
    )
),
eligible_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.admittime >= DATETIME(DATE(p.anchor_year, 1, 1))
    AND a.admittime <= DATETIME(DATE(p.anchor_year, 12, 31))
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 57 AND 67
),
admissions_with_diabetes AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN diabetes_codes dc ON di.icd_code = dc.icd_code AND di.icd_version = dc.icd_version
  JOIN eligible_admissions ea ON di.hadm_id = ea.hadm_id
),
admissions_with_hf AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN hf_codes hf ON di.icd_code = hf.icd_code AND di.icd_version = hf.icd_version
  JOIN eligible_admissions ea ON di.hadm_id = ea.hadm_id
),
cohort AS (
  SELECT hadm_id
  FROM admissions_with_diabetes
  INTERSECT DISTINCT
  SELECT hadm_id
  FROM admissions_with_hf
),
gla_prescriptions AS (
  SELECT p.hadm_id,
    p.starttime,
    a.admittime,
    a.dischtime,
    CASE 
      WHEN p.starttime >= a.admittime AND p.starttime <= DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
      THEN 1 ELSE 0 END AS in_first_48h,
    CASE 
      WHEN p.starttime >= DATETIME_ADD(a.dischtime, INTERVAL -12 HOUR) AND p.starttime <= a.dischtime
      THEN 1 ELSE 0 END AS in_final_12h
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.hadm_id = a.hadm_id
  JOIN cohort c ON p.hadm_id = c.hadm_id
  WHERE LOWER(p.drug) IN (
    'semaglutide', 'liraglutide', 'dulaglutide', 'exenatide', 'tirzepatide',
    'ozempic', 'victoza', 'trulicity', 'byetta', 'mounjaro'
  )
),
admission_flags AS (
  SELECT hadm_id,
    MAX(in_first_48h) AS had_gla_early,
    MAX(in_final_12h) AS had_gla_late
  FROM gla_prescriptions
  GROUP BY hadm_id
),
summary_stats AS (
  SELECT
    COUNT(*) AS total_admissions,
    AVG(had_gla_early) AS prop_early,
    AVG(had_gla_late) AS prop_late
  FROM admission_flags
)
SELECT
  ROUND(100 * prop_early, 2) AS prevalence_first_48h_pct,
  ROUND(100 * prop_late, 2) AS prevalence_final_12h_pct,
  ROUND(100 * (prop_late - prop_early), 2) AS absolute_change_pct,
  ROUND(
    CASE 
      WHEN prop_early > 0 THEN (prop_late / prop_early - 1) 
      ELSE NULL 
    END, 3
  ) AS relative_change_ratio
FROM summary_stats;