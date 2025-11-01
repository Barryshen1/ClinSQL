WITH sepsis_patients AS (
  -- Identify male patients aged 50-60 with sepsis (excluding septic shock)
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) < 8 THEN '<8 days' ELSE '>=8 days' END AS los_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (
      -- Sepsis codes (excluding septic shock)
      (di.icd_code LIKE 'A41.%' AND di.icd_code NOT LIKE 'A41.9') -- Other sepsis, excluding unspecified
      OR (di.icd_code LIKE 'R65.2%' AND di.icd_code != 'R65.21') -- Severe sepsis, excluding septic shock
      OR di.icd_code IN ('A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.8', 'A40.9') -- Streptococcal sepsis
      OR di.icd_code IN ('A41.0', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.8')
    )
    AND di.icd_code NOT IN ('R65.21', 'R57.2', 'A41.9') -- Exclude septic shock and unspecified sepsis
),

mortality_stats AS (
  -- Calculate mortality rates and 95% CIs
  SELECT
    los_category,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    -- Calculate mortality rate with 95% CI using Wilson score interval
    ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mortality_rate,
    -- Wilson score interval for 95% CI
    ROUND(
      (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) + 1.96*1.96/2) /
      (COUNT(*) + 1.96*1.96) +
      1.96*1.96/(4*(COUNT(*) + 1.96*1.96)) /
      SQRT(COUNT(*) + 1.96*1.96) *
      SQRT(
        4*SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)*(COUNT(*) - SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)) +
        1.96*1.96
      )
    * 100, 2) AS ci_upper,
    ROUND(
      (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) + 1.96*1.96/2) /
      (COUNT(*) + 1.96*1.96) -
      1.96*1.96/(4*(COUNT(*) + 1.96*1.96)) /
      SQRT(COUNT(*) + 1.96*1.96) *
      SQRT(
        4*SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)*(COUNT(*) - SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)) +
        1.96*1.96
      )
    * 100, 2) AS ci_lower
  FROM
    sepsis_patients
  GROUP BY
    los_category
),

median_time_to_death AS (
  -- Calculate median time-to-death for non-survivors
  SELECT
    los_category,
    PERCENTILE_CONT(TIMESTAMP_DIFF(deathtime, admittime, DAY), 0.5) OVER (PARTITION BY los_category) AS median_time_to_death
  FROM
    sepsis_patients
  WHERE
    hospital_expire_flag = 1
)

SELECT
  m.los_category,
  m.total_patients,
  m.deaths,
  m.mortality_rate,
  m.ci_lower,
  m.ci_upper,
  t.median_time_to_death
FROM
  mortality_stats m
LEFT JOIN
  median_time_to_death t ON m.los_category = t.los_category
GROUP BY
  m.los_category, m.total_patients, m.deaths, m.mortality_rate, m.ci_lower, m.ci_upper, t.median_time_to_death
ORDER BY
  m.los_category;