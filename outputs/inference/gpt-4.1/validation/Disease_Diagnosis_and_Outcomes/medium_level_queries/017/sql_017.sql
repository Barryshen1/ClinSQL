WITH sepsis_icd AS (
  -- ICD-9 sepsis: 99591, 99592; ICD-10 sepsis: A40.*, A41.*
  SELECT DISTINCT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  WHERE (
    (d.icd_version = 9 AND (d.icd_code IN ('99591', '99592') OR LEFT(d.icd_code,5) IN ('99591','99592')))
    OR
    (d.icd_version = 10 AND (LEFT(d.icd_code,3) IN ('A40','A41')))
  )
),
septic_shock_icd AS (
  -- ICD-9 septic shock: 78552; ICD-10 septic shock: R6521
  SELECT DISTINCT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  WHERE (
    (d.icd_version = 9 AND d.icd_code = '78552')
    OR
    (d.icd_version = 10 AND LEFT(d.icd_code,5) = 'R6521')
  )
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) < 8 THEN '<8' ELSE '≥8' END AS los_group,
    CASE WHEN a.hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) ELSE NULL END AS time_to_death_days
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN sepsis_icd s
    ON a.hadm_id = s.hadm_id
  LEFT JOIN septic_shock_icd ss
    ON a.hadm_id = ss.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND ss.hadm_id IS NULL -- exclude septic shock
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND p.anchor_age IS NOT NULL
),
agg AS (
  SELECT
    los_group,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate,
    -- Wilson score interval for 95% CI
    -- p̂ = deaths/n, n = n_admissions, z = 1.96
    SAFE_DIVIDE(
      (
        SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*))
        + (1.96*1.96)/(2*COUNT(*))
        - 1.96*SQRT(
          SAFE_DIVIDE(
            SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*))
            * (1 - SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)))
            + (1.96*1.96)/(4*COUNT(*)),
            COUNT(*)
          )
        )
      ),
      (1 + (1.96*1.96)/COUNT(*))
    ) AS ci_lower,
    SAFE_DIVIDE(
      (
        SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*))
        + (1.96*1.96)/(2*COUNT(*))
        + 1.96*SQRT(
          SAFE_DIVIDE(
            SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*))
            * (1 - SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)))
            + (1.96*1.96)/(4*COUNT(*)),
            COUNT(*)
          )
        )
      ),
      (1 + (1.96*1.96)/COUNT(*))
    ) AS ci_upper,
    -- Median time-to-death among non-survivors
    APPROX_QUANTILES(time_to_death_days, 2)[OFFSET(1)] AS median_time_to_death_days
  FROM cohort
  GROUP BY los_group
)
SELECT
  los_group,
  n_admissions,
  n_deaths,
  ROUND(mortality_rate*100,1) AS mortality_percent,
  ROUND(ci_lower*100,1) AS mortality_95ci_lower_percent,
  ROUND(ci_upper*100,1) AS mortality_95ci_upper_percent,
  median_time_to_death_days
FROM agg
ORDER BY los_group;