WITH patient_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 62 AND 72
),

-- Get all diagnoses per admission
diagnoses AS (
  SELECT
    di.hadm_id,
    di.icd_code,
    di.icd_version,
    d.long_title
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
),

-- Flag admissions with AMI
ami_cohort AS (
  SELECT
    pa.*
  FROM patient_ages pa
  WHERE EXISTS (
    SELECT 1 FROM diagnoses d
    WHERE d.hadm_id = pa.hadm_id
      AND d.icd_version = 10
      AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
  )
),

-- Exclude if shock or respiratory failure
exclusion_codes AS (
  SELECT hadm_id
  FROM diagnoses
  WHERE (icd_version = 10 AND (
    icd_code LIKE 'R57.0' OR -- cardiogenic shock
    icd_code LIKE 'T81.1%' OR -- postprocedural shock
    icd_code LIKE 'J96.0%' OR -- acute respiratory failure
    icd_code LIKE 'J96.1%' OR -- chronic respiratory failure
    icd_code LIKE 'J96.2%'    -- acute on chronic
  ))
),

-- Final cohort: AMI, female, age 62–72, no shock/respiratory failure
final_cohort AS (
  SELECT ac.*
  FROM ami_cohort ac
  WHERE ac.hadm_id NOT IN (SELECT hadm_id FROM exclusion_codes)
    AND ac.dischtime IS NOT NULL
),

-- Compute LOS and group
los_mortality AS (
  SELECT
    fc.hadm_id,
    fc.hospital_expire_flag,
    fc.los_days,
    -- Flags for comorbidities
    MAX(CASE WHEN d.long_title LIKE '%chronic kidney disease%' 
              OR (d.icd_code LIKE 'N18%' AND d.icd_version = 10) THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN d.long_title LIKE '%diabetes%' 
              OR (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%')
              THEN 1 ELSE 0 END) AS has_diabetes
  FROM final_cohort fc
  LEFT JOIN diagnoses d ON fc.hadm_id = d.hadm_id
  GROUP BY fc.hadm_id, fc.hospital_expire_flag, fc.los_days
),

-- Group by LOS category
grouped_stats AS (
  SELECT
    CASE WHEN los_days <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_group,
    COUNT(*) AS n,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(CAST(has_ckd AS FLOAT64)) AS ckd_prevalence,
    AVG(CAST(has_diabetes AS FLOAT64)) AS diabetes_prevalence
  FROM los_mortality
  GROUP BY los_group
)

-- Final output: statistics and differences
SELECT
  los_group,
  n,
  ROUND(mortality_rate * 100, 2) AS mortality_rate_percent,
  ROUND(ckd_prevalence * 100, 2) AS ckd_prevalence_percent,
  ROUND(diabetes_prevalence * 100, 2) AS diabetes_prevalence_percent
FROM grouped_stats

UNION ALL

-- Absolute difference
SELECT
  'Absolute difference' AS los_group,
  CAST(NULL AS INT64) AS n,
  ROUND(
    (SELECT mortality_rate FROM grouped_stats WHERE los_group = '>5 days') -
    (SELECT mortality_rate FROM grouped_stats WHERE los_group = '≤5 days')
    , 4
  ) * 100 AS mortality_rate_percent,
  ROUND(
    (SELECT ckd_prevalence FROM grouped_stats WHERE los_group = '>5 days') -
    (SELECT ckd_prevalence FROM grouped_stats WHERE los_group = '≤5 days')
    , 4
  ) * 100 AS ckd_prevalence_percent,
  ROUND(
    (SELECT diabetes_prevalence FROM grouped_stats WHERE los_group = '>5 days') -
    (SELECT diabetes_prevalence FROM grouped_stats WHERE los_group = '≤5 days')
    , 4
  ) * 100 AS diabetes_prevalence_percent;