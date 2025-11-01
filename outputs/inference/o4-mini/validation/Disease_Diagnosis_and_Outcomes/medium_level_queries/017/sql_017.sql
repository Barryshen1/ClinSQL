WITH sepsis_admissions AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%sepsis%'
    AND LOWER(dd.long_title) NOT LIKE '%septic shock%'
),
filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS time_to_death_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN sepsis_admissions s
      ON a.subject_id = s.subject_id
     AND a.hadm_id    = s.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) >= 0
),
stats AS (
  SELECT
    CASE
      WHEN los < 8 THEN '<8 days'
      ELSE '>=8 days'
    END AS los_group,
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS n_deaths,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS p,
    -- variance = p*(1-p)/n
    SAFE_DIVIDE(
      SAFE_MULTIPLY(
        SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)),
        SAFE_SUBTRACT(1, SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)))
      ),
      COUNT(*)
    ) AS var,
    -- median time-to-death among non-survivors
    APPROX_QUANTILES(
      IF(hospital_expire_flag = 1, time_to_death_days, NULL),
      2
    )[OFFSET(1)] AS median_time_to_death_days
  FROM
    filtered_admissions
  GROUP BY
    los_group
)
SELECT
  los_group,
  n_admissions,
  n_deaths,
  p AS mortality_rate,
  -- 95% CI, guard variance >=0, clamp to [0,1]
  GREATEST(p - 1.96 * SQRT(GREATEST(var, 0)), 0) AS ci_lower,
  LEAST(GREATEST(p + 1.96 * SQRT(GREATEST(var, 0)), 0), 1) AS ci_upper,
  median_time_to_death_days
FROM
  stats
ORDER BY
  los_group;