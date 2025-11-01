WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    p.gender,
    -- Calculate age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
),

-- Get diagnoses for each admission
diagnoses AS (
  SELECT
    di.hadm_id,
    di.icd_code,
    di.icd_version,
    d_icd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd
    ON di.icd_code = d_icd.icd_code AND di.icd_version = d_icd.icd_version
),

-- Flag admissions with AMI
ami_cohort AS (
  SELECT DISTINCT hadm_id
  FROM diagnoses
  WHERE icd_version = 10
    AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%')
),

-- Identify admissions with shock or respiratory failure (to exclude)
exclusion_conditions AS (
  SELECT DISTINCT hadm_id
  FROM diagnoses
  WHERE icd_version = 10
    AND (
      icd_code LIKE 'R57%'  -- Shock
      OR icd_code LIKE 'J96%'  -- Respiratory failure
    )
),

-- Final cohort: AMI, no shock/respiratory failure, female, age 66-76
cohort AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.deathtime,
    pa.hospital_expire_flag,
    pa.admission_type,
    -- Define LOS in days
    DATETIME_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
    -- Define admission category
    CASE
      WHEN LOWER(pa.admission_type) IN ('emergency', 'urgent') THEN 'emergent'
      WHEN LOWER(pa.admission_type) = 'elective' THEN 'non-emergent'
      ELSE 'other'
    END AS admission_category
  FROM patient_admissions pa
  INNER JOIN ami_cohort ami ON pa.hadm_id = ami.hadm_id
  WHERE pa.age_at_admit BETWEEN 66 AND 76
    AND pa.gender = 'F'
    AND pa.hadm_id NOT IN (SELECT hadm_id FROM exclusion_conditions)
),

-- Final analysis: group by LOS category and admission type
analysis_groups AS (
  SELECT
    *,
    -- Categorize LOS
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
      ELSE NULL
    END AS los_group
  FROM cohort
  WHERE los_days IS NOT NULL AND los_days >= 1  -- Ensure valid LOS
)

-- Aggregate: mortality % and median time-to-death
SELECT
  los_group,
  admission_category,
  -- In-hospital mortality (%)
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_rate_pct,
  -- Median time-to-death in days (only for deceased patients)
  APPROX_QUANTILES(
    CASE
      WHEN hospital_expire_flag = 1
      THEN DATETIME_DIFF(COALESCE(deathtime, dischtime), admittime, DAY)
    END,
    100
  )[OFFSET(50)] AS median_time_to_death_days
FROM analysis_groups
WHERE los_group IS NOT NULL
GROUP BY los_group, admission_category
HAVING COUNT(*) > 0
ORDER BY los_group, admission_category;