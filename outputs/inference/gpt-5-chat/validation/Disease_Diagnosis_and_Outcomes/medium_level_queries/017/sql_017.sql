WITH sepsis_admissions AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE (
    -- ICD-9 sepsis
    (di.icd_version = 9 AND (
      di.icd_code LIKE '038%' OR  -- septicemia
      di.icd_code IN ('99591','99592')
    ))
    OR
    -- ICD-10 sepsis
    (di.icd_version = 10 AND (
      di.icd_code LIKE 'A40%' OR
      di.icd_code LIKE 'A41%'
    ))
  )
),
septic_shock AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE (
    -- ICD-9 septic shock
    (di.icd_version = 9 AND di.icd_code = '78552')
    OR
    -- ICD-10 septic shock
    (di.icd_version = 10 AND di.icd_code = 'R6521')
  )
),
cohort AS (
  SELECT sa.subject_id, sa.hadm_id
  FROM sepsis_admissions sa
  LEFT JOIN septic_shock ss
    ON sa.subject_id = ss.subject_id AND sa.hadm_id = ss.hadm_id
  WHERE ss.hadm_id IS NULL -- exclude septic shock
),
cohort_with_demo AS (
  SELECT c.subject_id, c.hadm_id, p.gender, p.anchor_age,
         adm.admittime, adm.dischtime, adm.deathtime,
         adm.hospital_expire_flag,
         TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON c.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON c.subject_id = adm.subject_id AND c.hadm_id = adm.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
),
cohort_with_losgrp AS (
  SELECT *,
         CASE WHEN los_days < 8 THEN '<8 days' ELSE '≥8 days' END AS los_group,
         CASE 
           WHEN hospital_expire_flag = 1 AND deathtime IS NOT NULL 
           THEN TIMESTAMP_DIFF(deathtime, admittime, DAY)
           ELSE NULL 
         END AS time_to_death_days
  FROM cohort_with_demo
),
summary AS (
  SELECT
    los_group,
    COUNT(*) AS n_total,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate,
    -- Wilson score interval
    (
      (
        SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*))
        + (POWER(1.96,2)/(2*COUNT(*)))
        - 1.96 * SQRT(
            (SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*))
            * (1 - SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)))
            + POWER(1.96,2)/(4*POWER(COUNT(*),2))
            ) / COUNT(*)
          )
      )
      / (1 + (POWER(1.96,2)/COUNT(*)))
    ) AS ci_lower,
    (
      (
        SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*))
        + (POWER(1.96,2)/(2*COUNT(*)))
        + 1.96 * SQRT(
            (SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*))
            * (1 - SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)))
            + POWER(1.96,2)/(4*POWER(COUNT(*),2))
            ) / COUNT(*)
          )
      )
      / (1 + (POWER(1.96,2)/COUNT(*)))
    ) AS ci_upper,
    APPROX_QUANTILES(time_to_death_days, 100)[OFFSET(50)] AS median_time_to_death_days
  FROM cohort_with_losgrp
  GROUP BY los_group
)
SELECT
  los_group,
  n_total,
  n_deaths,
  ROUND(mortality_rate*100,1) AS mortality_pct,
  ROUND(ci_lower*100,1) AS ci_lower_pct,
  ROUND(ci_upper*100,1) AS ci_upper_pct,
  median_time_to_death_days
FROM summary
ORDER BY los_group;