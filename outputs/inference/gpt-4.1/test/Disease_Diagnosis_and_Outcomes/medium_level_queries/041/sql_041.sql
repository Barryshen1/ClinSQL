WITH female_50_60 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    -- Calculate LOS in days
    SAFE_CAST(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS INT64) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
, sepsis_admissions AS (
  -- Identify admissions with sepsis but NOT septic shock
  SELECT
    f.*
  FROM
    female_50_60 f
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON f.hadm_id = d.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      -- ICD-10 sepsis codes
      (d.icd_version = 10 AND (
        REGEXP_CONTAINS(d.icd_code, r'^A40') OR
        REGEXP_CONTAINS(d.icd_code, r'^A41') OR
        d.icd_code = 'R65.2'
      ))
      OR
      -- ICD-9 sepsis codes
      (d.icd_version = 9 AND (
        d.icd_code IN ('99591', '99592')
      ))
    )
    -- Exclude septic shock
    AND NOT (
      (d.icd_version = 10 AND d.icd_code = 'R65.21')
      OR
      (d.icd_version = 9 AND d.icd_code = '78552')
    )
)
, septic_shock_admissions AS (
  -- Admissions with septic shock codes
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 10 AND icd_code = 'R65.21')
    OR
    (icd_version = 9 AND icd_code = '78552')
)
, final_cohort AS (
  -- Remove admissions with septic shock
  SELECT
    s.*
  FROM
    sepsis_admissions s
  LEFT JOIN septic_shock_admissions ss
    ON s.hadm_id = ss.hadm_id
  WHERE
    ss.hadm_id IS NULL
)
, grouped AS (
  SELECT
    *,
    CASE
      WHEN los_days <= 7 THEN 'LOS <= 7'
      WHEN los_days > 7 THEN 'LOS > 7'
      ELSE NULL
    END AS los_group
  FROM
    final_cohort
  WHERE
    los_days IS NOT NULL
)
, mortality_stats AS (
  SELECT
    los_group,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS mortality_rate_pct
  FROM
    grouped
  WHERE
    los_group IS NOT NULL
  GROUP BY
    los_group
)
, time_to_death AS (
  SELECT
    los_group,
    SAFE_CAST(TIMESTAMP_DIFF(deathtime, admittime, DAY) AS INT64) AS time_to_death_days
  FROM
    grouped
  WHERE
    hospital_expire_flag = 1
    AND deathtime IS NOT NULL
    AND admittime IS NOT NULL
    AND deathtime >= admittime
    AND los_group IS NOT NULL
)
, median_time_to_death AS (
  SELECT
    los_group,
    APPROX_QUANTILES(time_to_death_days, 2)[OFFSET(1)] AS median_time_to_death_days
  FROM
    time_to_death
  GROUP BY
    los_group
)
, stats AS (
  SELECT
    m.los_group,
    m.n_admissions,
    m.n_deaths,
    m.mortality_rate_pct,
    mt.median_time_to_death_days
  FROM
    mortality_stats m
    LEFT JOIN median_time_to_death mt
      ON m.los_group = mt.los_group
)
-- Calculate absolute and relative difference
SELECT
  *,
  -- Absolute difference: LOS >7 minus LOS <=7
  (SELECT mortality_rate_pct FROM stats WHERE los_group = 'LOS > 7') -
  (SELECT mortality_rate_pct FROM stats WHERE los_group = 'LOS <= 7') AS absolute_difference_pct,
  -- Relative difference: (LOS >7 - LOS <=7) / LOS <=7
  SAFE_DIVIDE(
    (SELECT mortality_rate_pct FROM stats WHERE los_group = 'LOS > 7') -
    (SELECT mortality_rate_pct FROM stats WHERE los_group = 'LOS <= 7'),
    (SELECT mortality_rate_pct FROM stats WHERE los_group = 'LOS <= 7')
  ) AS relative_difference
FROM
  stats
ORDER BY
  los_group;