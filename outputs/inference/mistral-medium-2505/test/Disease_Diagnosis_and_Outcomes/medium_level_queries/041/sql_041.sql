WITH
-- Define sepsis and septic shock ICD codes
sepsis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%sepsis%' AND LOWER(long_title) NOT LIKE '%shock%'
),

septic_shock_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%septic shock%'
),

-- Get female patients aged 50-60
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 50 AND 60
),

-- Get admissions with sepsis (excluding septic shock)
sepsis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN '≤7 days' ELSE '>7 days' END AS los_group,
    TIMESTAMP_DIFF(a.deathtime, a.admittime, HOUR) AS time_to_death_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients p ON a.subject_id = p.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN sepsis_codes s ON d.icd_code = s.icd_code AND d.icd_version = '10'
    WHERE d.hadm_id = a.hadm_id
  )
  AND NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN septic_shock_codes s ON d.icd_code = s.icd_code AND d.icd_version = '10'
    WHERE d.hadm_id = a.hadm_id
  )
),

-- Calculate mortality metrics
mortality_metrics AS (
  SELECT
    los_group,
    COUNT(*) AS total_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mortality_percentage
  FROM sepsis_admissions
  GROUP BY los_group
),

-- Calculate median time to death for each LOS group
median_time_to_death AS (
  SELECT
    los_group,
    PERCENTILE_CONT(time_to_death_hours, 0.5) AS median_time_to_death_hours
  FROM sepsis_admissions
  WHERE hospital_expire_flag = 1
  GROUP BY los_group
),

-- Calculate differences between groups
differences AS (
  SELECT
    (SELECT mortality_percentage FROM mortality_metrics WHERE los_group = '>7 days') -
    (SELECT mortality_percentage FROM mortality_metrics WHERE los_group = '≤7 days') AS absolute_difference,
    CASE
      WHEN (SELECT mortality_percentage FROM mortality_metrics WHERE los_group = '≤7 days') = 0 THEN NULL
      ELSE ROUND(
        ((SELECT mortality_percentage FROM mortality_metrics WHERE los_group = '>7 days') -
        (SELECT mortality_percentage FROM mortality_metrics WHERE los_group = '≤7 days')) /
        (SELECT mortality_percentage FROM mortality_metrics WHERE los_group = '≤7 days') * 100, 2
      )
    END AS relative_difference_percentage
)

-- Final result
SELECT
  m.los_group,
  m.total_admissions,
  m.deaths,
  m.mortality_percentage,
  t.median_time_to_death_hours,
  d.absolute_difference,
  d.relative_difference_percentage
FROM mortality_metrics m
JOIN median_time_to_death t ON m.los_group = t.los_group
CROSS JOIN differences d
ORDER BY m.los_group;