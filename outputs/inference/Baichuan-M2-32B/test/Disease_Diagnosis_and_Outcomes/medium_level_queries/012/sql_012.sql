WITH 
-- Fix: ensure all string literals are properly quoted and UNION ALL is correctly formatted.
comorbidity_codes AS (
  SELECT 'CKD' AS comorbidity, '403.00' AS icd9, 'N18.1' AS icd10
  UNION ALL SELECT 'CKD', '403.01', 'N18.3'
  UNION ALL SELECT 'CKD', '403.02', 'N18.4'
  UNION ALL SELECT 'CKD', '403.10', 'N18.5'
  UNION ALL SELECT 'CKD', '403.11', 'N18.6'
  UNION ALL SELECT 'CKD', '403.12', 'N18.7'
  UNION ALL SELECT 'CKD', '403.90', 'N18.8'
  UNION ALL SELECT 'CKD', '403.91', 'N18.9'
  UNION ALL SELECT 'CKD', '404.00', 'N18.1'
  UNION ALL SELECT 'CKD', '404.01', 'N18.3'
  UNION ALL SELECT 'CKD', '404.02', 'N18.4'
  UNION ALL SELECT 'CKD', '404.10', 'N18.5'
  UNION ALL SELECT 'CKD', '404.11', 'N18.6'
  UNION ALL SELECT 'CKD', '404.12', 'N18.7'
  UNION ALL SELECT 'CKD', '404.90', 'N18.8'
  UNION ALL SELECT 'CKD', '404.91', 'N18.9'
  UNION ALL SELECT 'Diabetes', '250.00', 'E10.20'
  UNION ALL SELECT 'Diabetes', '250.01', 'E10.21'
  UNION ALL SELECT 'Diabetes', '250.02', 'E10.22'
  UNION ALL SELECT 'Diabetes', '250.10', 'E10.20'
  UNION ALL SELECT 'Diabetes', '250.11', 'E10.21'
  UNION ALL SELECT 'Diabetes', '250.12', 'E10.22'
  UNION ALL SELECT 'Diabetes', '250.20', 'E10.20'
  UNION ALL SELECT 'Diabetes', '250.21', 'E10.21'
  UNION ALL SELECT 'Diabetes', '250.22', 'E10.22'
  UNION ALL SELECT 'Diabetes', '250.30', 'E10.20'
  UNION ALL SELECT 'Diabetes', '250.31', 'E10.21'
  UNION ALL SELECT 'Diabetes', '250.32', 'E10.22'
  UNION ALL SELECT 'Diabetes', '250.40', 'E10.20'
  UNION ALL SELECT 'Diabetes', '250.41', 'E10.21'
  UNION ALL SELECT 'Diabetes', '250.42', 'E10.22'
  UNION ALL SELECT 'Diabetes', '250.50', 'E10.20'
  UNION ALL SELECT 'Diabetes', '250.51', 'E10.21'
  UNION ALL SELECT 'Diabetes', '250.52', 'E10.22'
  UNION ALL SELECT 'Diabetes', '250.60', 'E10.20'
  UNION ALL SELECT 'Diabetes', '250.61', 'E10.21'
  UNION ALL SELECT 'Diabetes', '250.62', 'E10.22'
  UNION ALL SELECT 'Diabetes', '250.70', 'E10.20'
  UNION ALL SELECT 'Diabetes', '250.71', 'E10.21'
  UNION ALL SELECT 'Diabetes', '250.72', 'E10.22'
  UNION ALL SELECT 'Diabetes', '250.80', 'E10.20'
  UNION ALL SELECT 'Diabetes', '250.81', 'E10.21'
  UNION ALL SELECT 'Diabetes', '250.82', 'E10.22'
  UNION ALL SELECT 'Diabetes', '250.90', 'E10.20'
  UNION ALL SELECT 'Diabetes', '250.91', 'E10.21'
  UNION ALL SELECT 'Diabetes', '250.92', 'E10.22'
  -- Add more as needed, but this is a sample
),
-- CTE for heart failure ICD codes
heart_failure_codes AS (
  SELECT '402.01' AS icd9, 'I50.10' AS icd10
  UNION ALL SELECT '402.91', 'I50.9'
  UNION ALL SELECT '404.01', 'I50.10'
  UNION ALL SELECT '404.03', 'I50.10'
  UNION ALL SELECT '404.11', 'I50.10'
  UNION ALL SELECT '404.13', 'I50.10'
  UNION ALL SELECT '404.91', 'I50.9'
  UNION ALL SELECT '404.93', 'I50.9'
  UNION ALL SELECT '428.0', 'I50.10'
  UNION ALL SELECT '428.1', 'I50.10'
  UNION ALL SELECT '428.2', 'I50.10'
  UNION ALL SELECT '428.3', 'I50.10'
  UNION ALL SELECT '428.4', 'I50.10'
  UNION ALL SELECT '428.9', 'I50.9'
  -- Add more as needed
),
-- Base cohort: women aged 83-93 with heart failure
base_cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission using anchor_year and anchor_age
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age,
    -- ICU indicator: whether there is an icustay for this hadm_id
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu,
    -- Compute LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
  -- Filter for women, age 83-93, and heart failure diagnosis
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN (SELECT icd9 FROM heart_failure_codes))
          OR (d.icd_version = 10 AND d.icd_code IN (SELECT icd10 FROM heart_failure_codes))
        )
    )
),
-- Comorbidity flags and count
comorbidity_flags AS (
  SELECT 
    b.*,
    -- Count distinct comorbidities
    COUNT(DISTINCT c.comorbidity) AS comorbidity_count,
    -- Flags for CKD and diabetes
    MAX(CASE WHEN c.comorbidity = 'CKD' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN c.comorbidity = 'Diabetes' THEN 1 ELSE 0 END) AS has_diabetes
  FROM base_cohort b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON b.subject_id = d.subject_id AND b.hadm_id = d.hadm_id
  LEFT JOIN comorbidity_codes c 
    ON (d.icd_version = 9 AND d.icd_code = c.icd9) 
    OR (d.icd_version = 10 AND d.icd_code = c.icd10)
  GROUP BY b.subject_id, b.hadm_id, b.admittime, b.dischtime, b.hospital_expire_flag, b.age, b.icu, b.los_days
),
-- Stratification groups
stratified AS (
  SELECT 
    *,
    CASE 
      WHEN icu = 1 THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_group,
    CASE 
      WHEN los_days < 8 THEN '<8'
      ELSE '>=8'
    END AS los_group,
    CASE 
      WHEN comorbidity_count <= 1 THEN '0-1'
      WHEN comorbidity_count = 2 THEN '2'
      ELSE '>=3'
    END AS comorbidity_burden_group
  FROM comorbidity_flags
)
-- Final aggregation
SELECT 
  icu_group,
  los_group,
  comorbidity_burden_group,
  COUNT(*) AS num_patients,
  -- Mortality percentage
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  -- Median LOS
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  -- CKD prevalence
  AVG(has_ckd) * 100 AS ckd_prevalence_percent,
  -- Diabetes prevalence
  AVG(has_diabetes) * 100 AS diabetes_prevalence_percent
FROM stratified
GROUP BY icu_group, los_group, comorbidity_burden_group
ORDER BY icu_group, los_group, comorbidity_burden_group;