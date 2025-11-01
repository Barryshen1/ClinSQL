WITH sepsis_cohort AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Time to death in days (for non-survivors)
    CASE WHEN adm.hospital_expire_flag = 1 THEN
      DATETIME_DIFF(adm.deathtime, adm.admittime, DAY) 
    END AS time_to_death_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 50 AND 60
    AND (d.icd_code LIKE 'A41%' OR d.icd_code = 'R65.20')
    -- Exclude septic shock (R65.21)
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag2
      WHERE adm.hadm_id = diag2.hadm_id
        AND diag2.icd_code = 'R65.21'
        AND diag2.icd_version = 10
    )
),

los_groups AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    time_to_death_days,
    CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END AS los_group
  FROM sepsis_cohort
),

mortality_agg AS (
  SELECT
    los_group,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    -- Wilson score interval for 95% CI
    -- Lower bound: (p + z^2/(2n) - z * sqrt((p*(1-p) + z^2/(4n)) / n)) / (1 + z^2/n)
    -- Upper bound: (p + z^2/(2n) + z * sqrt((p*(1-p) + z^2/(4n)) / n)) / (1 + z^2/n)
    -- z = 1.96 for 95% CI
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100 AS mortality_percent,
    (SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) + (1.96*1.96)/(2*COUNT(*)) - 1.96 * SQRT((SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*))*(1-SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*))) + (1.96*1.96)/(4*COUNT(*))) / COUNT(*))) / (1 + (1.96*1.96)/COUNT(*)) * 100 AS ci_lower,
    (SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) + (1.96*1.96)/(2*COUNT(*)) + 1.96 * SQRT((SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*))*(1-SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*))) + (1.96*1.96)/(4*COUNT(*))) / COUNT(*))) / (1 + (1.96*1.96)/COUNT(*)) * 100 AS ci_upper
  FROM los_groups
  GROUP BY los_group
),

time_to_death_median AS (
  SELECT
    los_group,
    PERCENTILE_CONT(time_to_death_days, 0.5) OVER (PARTITION BY los_group) AS median_time_to_death
  FROM los_groups
  WHERE hospital_expire_flag = 1
)

SELECT
  m.los_group,
  m.total_patients,
  m.deaths,
  ROUND(m.mortality_percent, 2) AS mortality_percent,
  ROUND(m.ci_lower, 2) AS ci_lower_95,
  ROUND(m.ci_upper, 2) AS ci_upper_95,
  ROUND(t.median_time_to_death, 2) AS median_time_to_death_days
FROM mortality_agg m
LEFT JOIN (
  SELECT DISTINCT los_group, median_time_to_death
  FROM time_to_death_median
) t ON m.los_group = t.los_group
ORDER BY m.los_group;