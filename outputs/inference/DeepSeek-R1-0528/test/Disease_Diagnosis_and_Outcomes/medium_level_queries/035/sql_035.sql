WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    -- Calculate LOS in calendar days
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    -- Upper GI bleed flag (ICD-9 and ICD-10)
    MAX(CASE 
          WHEN (diag.icd_version = 9 AND diag.icd_code IN ('530.7', '530.82', '578.0', '531.00', '531.01', '531.20', '531.21', '531.40', '531.41', '531.60', '531.61', '532.00', '532.01', '532.20', '532.21', '532.40', '532.41', '532.60', '532.61', '533.00', '533.01', '533.20', '533.21', '533.40', '533.41', '533.60', '533.61', '534.00', '534.01', '534.20', '534.21', '534.40', '534.41', '534.60', '534.61'))
               OR (diag.icd_version = 10 AND diag.icd_code IN ('K25.0', 'K25.2', 'K25.4', 'K25.6', 'K26.0', 'K26.2', 'K26.4', 'K26.6', 'K27.0', 'K27.2', 'K27.4', 'K27.6', 'K28.0', 'K28.2', 'K28.4', 'K28.6', 'K92.0', 'K92.1', 'K92.2'))
          THEN 1 ELSE 0 
        END) AS has_upper,
    -- Lower GI bleed flag (ICD-9 and ICD-10)
    MAX(CASE 
          WHEN (diag.icd_version = 9 AND diag.icd_code IN ('569.3', '578.1', '455.2', '455.5', '455.8', '455.9', '562.02', '562.03', '562.12', '562.13'))
               OR (diag.icd_version = 10 AND diag.icd_code IN ('K62.5', 'K62.3', 'K57.01', 'K57.03', 'K57.11', 'K57.13', 'K57.21', 'K57.23', 'K57.31', 'K57.33', 'K57.41', 'K57.43', 'K57.51', 'K57.53', 'K57.81', 'K57.83', 'K57.91', 'K57.93', 'I84.0', 'I84.1', 'I84.2', 'I84.3', 'I84.4', 'I84.5', 'I84.6', 'I84.7', 'I84.8', 'I84.9'))
          THEN 1 ELSE 0 
        END) AS has_lower,
    -- ICU Day 1 flag (within 24h of admission AND after admission)
    MAX(CASE WHEN i.intime IS NOT NULL AND TIMESTAMP_DIFF(i.intime, a.admittime, HOUR) BETWEEN 0 AND 24 THEN 1 ELSE 0 END) AS icu_day1,
    -- Any ICU stay flag
    MAX(CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_ever
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON a.hadm_id = diag.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_age, p.anchor_year, p.gender
),
cohort AS (
  SELECT *,
    CASE 
      WHEN has_upper = 1 AND has_lower = 0 THEN 'Upper'
      WHEN has_lower = 1 AND has_upper = 0 THEN 'Lower'
      ELSE NULL 
    END AS gi_type
  FROM base
  WHERE 
    age BETWEEN 69 AND 79
    AND los_days >= 1
    AND ( (has_upper = 1 AND has_lower = 0) OR (has_lower = 1 AND has_upper = 0) )
),
-- mortality analysis by LOS group and ICU day1 status
mortality_data AS (
  SELECT 
    gi_type,
    CASE 
      WHEN los_days BETWEEN 1 AND 2 THEN '1-2'
      WHEN los_days BETWEEN 3 AND 5 THEN '3-5'
      WHEN los_days BETWEEN 6 AND 9 THEN '6-9'
      WHEN los_days >= 10 THEN '>=10'
    END AS los_group,
    CASE icu_day1 WHEN 1 THEN 'Yes' ELSE 'No' END AS icu_day1,
    COUNT(hadm_id) AS total_admissions,
    SUM(hospital_expire_flag) AS total_deaths,
    ROUND(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(hadm_id)) * 100, 2) AS mortality_rate
  FROM cohort
  GROUP BY gi_type, los_group, icu_day1
),
-- ICU admission rates by GI type
icu_admission_data AS (
  SELECT 
    gi_type,
    COUNT(hadm_id) AS total_admissions,
    SUM(icu_ever) AS total_icu_admissions,
    ROUND(SAFE_DIVIDE(SUM(icu_ever), COUNT(hadm_id)) * 100, 2) AS icu_admission_rate
  FROM cohort
  GROUP BY gi_type
)
-- Combine results for final output
SELECT 
  'mortality' AS report_type,
  gi_type,
  los_group,
  icu_day1,
  total_admissions,
  total_deaths,
  mortality_rate,
  NULL AS total_icu_admissions,
  NULL AS icu_admission_rate
FROM mortality_data
UNION ALL
SELECT 
  'icu_admission' AS report_type,
  gi_type,
  NULL AS los_group,
  NULL AS icu_day1,
  total_admissions,
  NULL AS total_deaths,
  NULL AS mortality_rate,
  total_icu_admissions,
  icu_admission_rate
FROM icu_admission_data
ORDER BY report_type, gi_type, los_group, icu_day1;