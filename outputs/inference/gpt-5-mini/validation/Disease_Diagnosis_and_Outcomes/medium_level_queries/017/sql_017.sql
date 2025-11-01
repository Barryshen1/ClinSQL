WITH sepsis_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
   AND d.icd_version = di.icd_version
  WHERE LOWER(di.long_title) LIKE '%sepsis%'
),
shock_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
   AND d.icd_version = di.icd_version
  WHERE LOWER(di.long_title) LIKE '%septic shock%'
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) AS time_to_death_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.hadm_id IN (SELECT hadm_id FROM sepsis_hadm)
    AND a.hadm_id NOT IN (SELECT hadm_id FROM shock_hadm)
),
agg AS (
  SELECT
    CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END AS los_group,
    COUNT(1) AS n,
    SUM(IF(hospital_expire_flag = 1, 1, 0)) AS deaths,
    SAFE_DIVIDE(SUM(IF(hospital_expire_flag = 1, 1, 0)), COUNT(1)) AS p,
    -- median time-to-death among non-survivors (days). APPROX_QUANTILES ignores NULLs.
    APPROX_QUANTILES(
      IF(hospital_expire_flag = 1, time_to_death_days, NULL),
      2
    )[OFFSET(1)] AS median_time_to_death_days
  FROM cohort
  GROUP BY los_group
)
SELECT
  los_group,
  n AS admissions,
  deaths,
  -- mortality percent
  ROUND(100 * p, 3) AS mortality_pct,
  -- 95% CI using normal approximation, clamped to [0,1], reported as percent
  CASE
    WHEN n > 0 THEN ROUND(100 * GREATEST(0, p - 1.96 * SQRT(SAFE_DIVIDE(p * (1 - p), n))), 3)
    ELSE NULL
  END AS mortality_ci_lower_pct,
  CASE
    WHEN n > 0 THEN ROUND(100 * LEAST(1, p + 1.96 * SQRT(SAFE_DIVIDE(p * (1 - p), n))), 3)
    ELSE NULL
  END AS mortality_ci_upper_pct,
  -- median time-to-death among non-survivors (days); NULL if no deaths in group
  median_time_to_death_days
FROM agg
ORDER BY los_group;