WITH hf AS (
  -- Identify female patients aged 80-90 with heart failure diagnoses
  -- Deduplicate admissions to avoid multiple HF rows for the same admission
  SELECT DISTINCT
         a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         a.deathtime,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
         IF(a.deathtime IS NOT NULL,
            TIMESTAMP_DIFF(a.deathtime, a.admittime, SECOND) / 86400.0,
            NULL) AS death_time_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (di.icd_code LIKE '428%' OR di.icd_code LIKE 'I50%')
),
grouped AS (
  SELECT
     CASE
       WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
       WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
       WHEN los_days >= 8 THEN '>=8'
     END AS los_group,
     deathtime,
     death_time_days
  FROM hf
  WHERE los_days IS NOT NULL
),
agg AS (
  -- Mortality counts by LOS group
  SELECT
     los_group,
     COUNT(*) AS n_adm,
     SUM(CASE WHEN deathtime IS NOT NULL THEN 1 ELSE 0 END) AS n_deaths
  FROM grouped
  WHERE los_group IS NOT NULL
  GROUP BY los_group
),
med AS (
  -- Median time-to-death (in days) by LOS group
  SELECT
     los_group,
     APPROX_QUANTILES(death_time_days, 100)[OFFSET(50)] AS median_time_to_death_days
  FROM grouped
  WHERE death_time_days IS NOT NULL
  GROUP BY los_group
)
SELECT
  a.los_group,
  a.n_adm,
  a.n_deaths,
  100.0 * SAFE_DIVIDE(a.n_deaths, a.n_adm) AS mortality_percentage,
  CASE
    -- 95% CI lower bound (%)
    WHEN a.n_adm > 0 THEN
      100.0 * ( SAFE_DIVIDE(a.n_deaths, a.n_adm)
               - 1.96 * SQRT( SAFE_DIVIDE(a.n_deaths, a.n_adm) * (1 - SAFE_DIVIDE(a.n_deaths, a.n_adm)) / a.n_adm ) )
  END AS ci_lower_percent,
  CASE
    -- 95% CI upper bound (%)
    WHEN a.n_adm > 0 THEN
      100.0 * ( SAFE_DIVIDE(a.n_deaths, a.n_adm)
               + 1.96 * SQRT( SAFE_DIVIDE(a.n_deaths, a.n_adm) * (1 - SAFE_DIVIDE(a.n_deaths, a.n_adm)) / a.n_adm ) )
  END AS ci_upper_percent,
  m.median_time_to_death_days
FROM agg AS a
LEFT JOIN med AS m
  ON a.los_group = m.los_group
ORDER BY a.los_group;