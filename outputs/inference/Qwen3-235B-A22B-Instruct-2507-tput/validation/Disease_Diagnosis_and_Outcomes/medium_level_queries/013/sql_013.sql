WITH hf_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND di.icd_version = 10
    AND d.icd_code IN ('I50.21', 'I50.22', 'I50.23', 'I11.0') -- Acute HF codes
    AND (a.admittime >= DATETIME(p.anchor_year, 1, 1, 0, 0, 0))
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 80 AND 90
),
los_and_death AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) >= 8 THEN '>=8 days'
      ELSE NULL
    END AS los_group,
    DATETIME_DIFF(deathtime, admittime, HOUR) AS hours_to_death
  FROM hf_admissions
  WHERE dischtime IS NOT NULL
    AND admittime IS NOT NULL
    AND DATETIME_DIFF(dischtime, admittime, DAY) >= 1  -- At least 1 day LOS
),
mortality_stats AS (
  SELECT
    los_group,
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS n_deaths,
    APPROX_QUANTILES(IF(hospital_expire_flag = 1, hours_to_death, NULL), 100)[OFFSET(50)] AS median_hours_to_death
  FROM los_and_death
  WHERE los_group IS NOT NULL
  GROUP BY los_group
)
SELECT
  los_group,
  n_admissions,
  n_deaths,
  ROUND(100.0 * n_deaths / n_admissions, 2) AS mortality_rate_pct,
  -- Wilson score interval for 95% CI
  ROUND(100.0 * (n_deaths + 1.92) / (n_admissions + 3.84) - 1.96 * SQRT((n_deaths * (n_admissions - n_deaths) / n_admissions + 0.96) / (n_admissions + 3.84)) / (n_admissions + 3.84), 2) AS lower_95ci,
  ROUND(100.0 * (n_deaths + 1.92) / (n_admissions + 3.84) + 1.96 * SQRT((n_deaths * (n_admissions - n_deaths) / n_admissions + 0.96) / (n_admissions + 3.84)) / (n_admissions + 3.84), 2) AS upper_95ci,
  median_hours_to_death
FROM mortality_stats
ORDER BY
  CASE los_group
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
    WHEN '>=8 days' THEN 3
  END;