WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    -- Compute age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
-- Get all ICD diagnoses for each admission
diagnoses AS (
  SELECT
    di.hadm_id,
    di.icd_code,
    di.icd_version,
    d_icd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON di.icd_code = d_icd.icd_code AND di.icd_version = d_icd.icd_version
),
-- Identify sepsis admissions (with sepsis code) and exclude those with septic shock
sepsis_candidates AS (
  SELECT DISTINCT hadm_id
  FROM diagnoses
  WHERE (icd_version = 10 AND (
    icd_code LIKE 'A41%' OR 
    icd_code LIKE 'A40%' OR 
    icd_code = 'T8144'))
),
septic_shock_admissions AS (
  SELECT DISTINCT hadm_id
  FROM diagnoses
  WHERE icd_version = 10 AND icd_code = 'R6521'
),
sepsis_no_shock AS (
  SELECT sc.hadm_id
  FROM sepsis_candidates sc
  WHERE NOT EXISTS (
    SELECT 1 FROM septic_shock_admissions ss WHERE ss.hadm_id = sc.hadm_id
  )
),
-- Final cohort: sepsis without shock, male, age 50-60
cohort AS (
  SELECT
    pa.hadm_id,
    pa.subject_id,
    pa.age_at_admission,
    pa.admittime,
    pa.dischtime,
    pa.deathtime,
    pa.hospital_expire_flag,
    pa.los_days,
    -- Time to death in days (for non-survivors)
    CASE
      WHEN pa.hospital_expire_flag = 1 THEN
        DATETIME_DIFF(
          COALESCE(pa.deathtime, pa.dischtime),
          pa.admittime,
          DAY
        )
      ELSE NULL
    END AS days_to_death
  FROM patient_admissions pa
  INNER JOIN sepsis_no_shock sns ON pa.hadm_id = sns.hadm_id
  WHERE pa.age_at_admission >= 50 AND pa.age_at_admission <= 60
),
-- Group by LOS category
cohort_with_los_group AS (
  SELECT
    *,
    CASE
      WHEN los_days < 8 THEN '<8'
      WHEN los_days >= 8 THEN '>=8'
      ELSE NULL
    END AS los_group
  FROM cohort
  WHERE los_days IS NOT NULL
)
-- Final aggregation
SELECT
  los_group,
  COUNT(*) AS n_admissions,
  SUM(hospital_expire_flag) AS n_deaths,
  COUNT(*) - SUM(hospital_expire_flag) AS n_survivors,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_rate_percent,
  -- 95% CI for proportion: normal approximation
  ROUND(100.0 * (
    (SUM(hospital_expire_flag) / COUNT(*)) - 
    1.96 * SQRT( (SUM(hospital_expire_flag) / COUNT(*)) * (1 - SUM(hospital_expire_flag) / COUNT(*)) / COUNT(*) )
  ), 2) AS lower_95ci_percent,
  ROUND(100.0 * (
    (SUM(hospital_expire_flag) / COUNT(*)) + 
    1.96 * SQRT( (SUM(hospital_expire_flag) / COUNT(*)) * (1 - SUM(hospital_expire_flag) / COUNT(*)) / COUNT(*) )
  ), 2) AS upper_95ci_percent,
  -- Median time to death among non-survivors
  APPROX_QUANTILES(days_to_death, 2)[OFFSET(1)] AS median_time_to_death_days
FROM cohort_with_los_group
GROUP BY los_group
ORDER BY los_group;