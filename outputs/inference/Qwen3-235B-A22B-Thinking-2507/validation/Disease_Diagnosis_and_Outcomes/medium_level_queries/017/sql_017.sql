WITH sepsis_admissions AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%')
  GROUP BY hadm_id
),
shock_admissions AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND icd_code = 'R6521'
  GROUP BY hadm_id
),
sepsis_no_shock AS (
  SELECT sa.hadm_id
  FROM sepsis_admissions sa
  LEFT JOIN shock_admissions sh ON sa.hadm_id = sh.hadm_id
  WHERE sh.hadm_id IS NULL
),
cohort AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    a.admittime,
    a.deathtime,
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    -- Hospital LOS in days
    DATETIME_DIFF(CAST(a.dischtime AS DATETIME), CAST(a.admittime AS DATETIME), DAY) AS hospital_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN sepsis_no_shock sns
    ON a.hadm_id = sns.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 50 AND 60
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
cohort_with_los_group AS (
  SELECT
    *,
    CASE 
      WHEN hospital_los_days < 8 THEN '<8'
      ELSE '>=8'
    END AS los_group,
    -- Time-to-death in days (for non-survivors only)
    IF(hospital_expire_flag = 1, 
       DATETIME_DIFF(CAST(deathtime AS DATETIME), CAST(admittime AS DATETIME), DAY), 
       NULL) AS time_to_death
  FROM cohort
)
SELECT
  los_group,
  -- Mortality rate (%)
  ROUND(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100, 2) AS mortality_rate,
  -- 95% CI lower bound (%)
  ROUND(GREATEST(0, 
    (p - 1.96 * SQRT(SAFE_DIVIDE(p * (1 - p), COUNT(*)))) * 100
  ), 2) AS lower_ci,
  -- 95% CI upper bound (%)
  ROUND(LEAST(100, 
    (p + 1.96 * SQRT(SAFE_DIVIDE(p * (1 - p), COUNT(*)))) * 100
  ), 2) AS upper_ci,
  -- Median time-to-death (days) for non-survivors
  APPROX_QUANTILES(time_to_death, 100)[OFFSET(50)] AS median_time_to_death
FROM (
  SELECT
    *,
    SAFE_DIVIDE(SUM(hospital_expire_flag) OVER (PARTITION BY los_group), COUNT(*) OVER (PARTITION BY los_group)) AS p
  FROM cohort_with_los_group
)
GROUP BY los_group, p
ORDER BY los_group;