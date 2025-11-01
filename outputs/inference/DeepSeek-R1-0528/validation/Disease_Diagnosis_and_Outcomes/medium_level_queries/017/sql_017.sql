WITH sepsis_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^(038|99591|99592)')) OR
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^(A40|A41|R6520)'))
  )  -- Added missing parenthesis
), 
shock_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND icd_code = '78552') OR
    (icd_version = 10 AND icd_code = 'R6521')
  )  -- Added missing parenthesis
),
cohort AS (
  SELECT 
    adm.hadm_id,
    adm.subject_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    pat.gender,
    pat.anchor_age,
    pat.anchor_year,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN sepsis_admissions sep 
    ON adm.hadm_id = sep.hadm_id
  LEFT JOIN shock_admissions shock 
    ON adm.hadm_id = shock.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
    ON adm.subject_id = pat.subject_id
  WHERE 
    shock.hadm_id IS NULL  -- Exclude septic shock
    AND pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) 
        BETWEEN 50 AND 60
),
cohort_groups AS (
  SELECT 
    *,
    CASE WHEN los < 8 THEN '<8' ELSE '>=8' END AS los_group
  FROM cohort
),
mortality AS (
  SELECT 
    los_group,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS death_count,
    (SUM(hospital_expire_flag) / COUNT(*)) * 100 AS mortality_rate,
    -- 95% CI using normal approximation
    ((SUM(hospital_expire_flag) / COUNT(*)) - 
      1.96 * SQRT((SUM(hospital_expire_flag) / COUNT(*)) * 
      (1 - SUM(hospital_expire_flag) / COUNT(*)) / COUNT(*))) * 100 AS lower_ci,
    ((SUM(hospital_expire_flag) / COUNT(*)) + 
      1.96 * SQRT((SUM(hospital_expire_flag) / COUNT(*)) * 
      (1 - SUM(hospital_expire_flag) / COUNT(*)) / COUNT(*))) * 100 AS upper_ci
  FROM cohort_groups
  GROUP BY los_group
),
time_to_death AS (
  SELECT 
    los_group,
    APPROX_QUANTILES(
      DATE_DIFF(deathtime, admittime, DAY), 2
    )[OFFSET(1)] AS median_time_to_death_days
  FROM cohort_groups
  WHERE hospital_expire_flag = 1
  GROUP BY los_group
)
SELECT 
  m.los_group,
  m.total_patients,
  m.death_count,
  ROUND(m.mortality_rate, 2) AS mortality_rate,
  ROUND(m.lower_ci, 2) AS lower_ci_95,
  ROUND(m.upper_ci, 2) AS upper_ci_95,
  COALESCE(t.median_time_to_death_days, 0) AS median_time_to_death_days
FROM mortality m
LEFT JOIN time_to_death t 
  ON m.los_group = t.los_group
ORDER BY m.los_group;