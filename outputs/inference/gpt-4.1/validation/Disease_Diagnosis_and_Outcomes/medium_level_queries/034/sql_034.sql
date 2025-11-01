WITH heart_failure_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- Calculate LOS in days (may be fractional, so use CEIL for grouping)
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
)
, cohort AS (
  -- Only keep one row per admission (hadm_id)
  SELECT DISTINCT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    gender,
    anchor_age,
    los_days,
    CASE
      WHEN los_days < 8 THEN '<8'
      ELSE '>=8'
    END AS los_group
  FROM heart_failure_admissions
)
, stats AS (
  SELECT
    los_group,
    COUNT(*) AS admission_count,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_rate_percent
  FROM cohort
  GROUP BY los_group
)
, median_time_to_death AS (
  SELECT
    los_group,
    APPROX_QUANTILES(DATETIME_DIFF(deathtime, admittime, DAY), 2)[OFFSET(1)] AS median_time_to_death_days
  FROM cohort
  WHERE hospital_expire_flag = 1
    AND deathtime IS NOT NULL
  GROUP BY los_group
)
SELECT
  s.los_group,
  s.admission_count AS N,
  s.mortality_rate_percent AS in_hospital_mortality_rate_percent,
  m.median_time_to_death_days
FROM
  stats s
LEFT JOIN
  median_time_to_death m
ON s.los_group = m.los_group
ORDER BY
  CASE WHEN s.los_group = '<8' THEN 0 ELSE 1 END
;