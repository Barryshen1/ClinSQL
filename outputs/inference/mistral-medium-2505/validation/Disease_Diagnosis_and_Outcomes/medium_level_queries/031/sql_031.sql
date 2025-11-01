WITH
-- Define sepsis and septic shock ICD codes
sepsis_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN (
    '995.91', '995.92', '785.52',  -- ICD-9
    'R65.20', 'R65.21', 'A41.9'    -- ICD-10
  )
),

-- Get female patients aged 53-63 with sepsis/septic shock admissions
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime,
    p.anchor_age,
    d.icd_code,
    d.icd_version,
    CASE
      WHEN d.icd_code IN ('995.92', '785.52', 'R65.21') THEN 'Septic Shock'
      ELSE 'Sepsis'
    END AS sepsis_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN sepsis_codes d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.hospital_expire_flag IS NOT NULL
),

-- Categorize by LOS and sepsis type
categorized_admissions AS (
  SELECT
    hadm_id,
    sepsis_type,
    CASE WHEN los_days <= 7 THEN '≤7 days' ELSE '>7 days' END AS los_category,
    hospital_expire_flag,
    deathtime,
    TIMESTAMP_DIFF(deathtime, admittime, DAY) AS time_to_death_days
  FROM patient_admissions
  WHERE los_days IS NOT NULL
),

-- Aggregate results
results AS (
  SELECT
    sepsis_type,
    los_category,
    COUNT(DISTINCT hadm_id) AS n,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT hadm_id), 1) AS mortality_pct,
    ROUND(APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 1 THEN time_to_death_days ELSE NULL END, 100)[OFFSET(50)], 1) AS median_time_to_death
  FROM categorized_admissions
  GROUP BY sepsis_type, los_category
)

-- Final output with mortality differences
SELECT
  sepsis_type,
  los_category,
  n,
  mortality_pct,
  median_time_to_death,
  -- Calculate absolute and relative mortality differences
  FIRST_VALUE(mortality_pct) OVER (PARTITION BY sepsis_type ORDER BY los_category) AS reference_mortality,
  mortality_pct - FIRST_VALUE(mortality_pct) OVER (PARTITION BY sepsis_type ORDER BY los_category) AS absolute_diff,
  ROUND((mortality_pct - FIRST_VALUE(mortality_pct) OVER (PARTITION BY sepsis_type ORDER BY los_category)) /
        NULLIF(FIRST_VALUE(mortality_pct) OVER (PARTITION BY sepsis_type ORDER BY los_category), 0) * 100, 1) AS relative_diff_pct
FROM results
ORDER BY sepsis_type, los_category;