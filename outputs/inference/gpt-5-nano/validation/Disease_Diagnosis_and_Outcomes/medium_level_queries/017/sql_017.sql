WITH sepsis_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN a.deathtime IS NOT NULL THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) END AS days_to_death
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE
    p.gender IN ('M', 'Male')
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%sepsis%'
          OR LOWER(dd.long_title) LIKE '%septicemia%'
          OR di.icd_code LIKE 'A41%'
          OR di.icd_code LIKE 'A40%'
          OR di.icd_code LIKE '038%'
        )
        AND LOWER(dd.long_title) NOT LIKE '%shock%'
    )
)

SELECT
  base.los_group,
  base.n,
  base.deaths,
  CASE WHEN base.n > 0 THEN SAFE_DIVIDE(base.deaths, base.n) * 100.0 ELSE NULL END AS mortality_percent,
  CASE
    WHEN base.n = 0 THEN NULL
    ELSE (
      ((SAFE_DIVIDE(base.deaths, base.n) + (1.959963984540054*1.959963984540054)/(2.0*base.n))
       - 1.959963984540054 * SQRT( (SAFE_DIVIDE(base.deaths, base.n) * (1.0 - SAFE_DIVIDE(base.deaths, base.n)) + (1.959963984540054*1.959963984540054)/(4.0*base.n)) / base.n)
      ) / (1.0 + (1.959963984540054*1.959963984540054)/base.n)
    ) * 100.0
  END AS lower_ci_percent,
  CASE
    WHEN base.n = 0 THEN NULL
    ELSE (
      ((SAFE_DIVIDE(base.deaths, base.n) + (1.959963984540054*1.959963984540054)/(2.0*base.n))
       + 1.959963984540054 * SQRT( (SAFE_DIVIDE(base.deaths, base.n) * (1.0 - SAFE_DIVIDE(base.deaths, base.n)) + (1.959963984540054*1.959963984540054)/(4.0*base.n)) / base.n)
      ) / (1.0 + (1.959963984540054*1.959963984540054)/base.n)
    ) * 100.0
  END AS upper_ci_percent,
  med.median_days_to_death
FROM (
  SELECT
    CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END AS los_group,
    COUNT(*) AS n,
    SUM(CASE WHEN deathtime IS NOT NULL THEN 1 ELSE 0 END) AS deaths
  FROM sepsis_cohort
  GROUP BY CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END
) AS base
LEFT JOIN (
  SELECT
    CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END AS los_group,
    APPROX_QUANTILES(days_to_death, 2)[OFFSET(1)] AS median_days_to_death
  FROM sepsis_cohort
  WHERE deathtime IS NOT NULL
  GROUP BY CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END
) AS med
  ON base.los_group = med.los_group
ORDER BY base.los_group;