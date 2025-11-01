WITH cohort AS (
  -- Select admissions for women aged 80-90 with acute decompensated HF
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    -- Acute decompensated HF: ICD-9 428.x, ICD-10 I50.x, but restrict to "acute" in long_title
    AND (
      (dd.icd_version = 9 AND dd.icd_code LIKE '428%')
      OR (dd.icd_version = 10 AND dd.icd_code LIKE 'I50%')
    )
    AND LOWER(dd.long_title) LIKE '%acute%'
    -- Valid dates
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
los_groups AS (
  -- Assign LOS group
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '8+'
      ELSE NULL
    END AS los_group,
    -- Time to death in days (for deaths only)
    CASE
      WHEN hospital_expire_flag = 1 AND deathtime IS NOT NULL
        THEN DATETIME_DIFF(deathtime, admittime, DAY)
      ELSE NULL
    END AS time_to_death_days
  FROM cohort
  WHERE los_days >= 1 -- Exclude LOS <1 day or negative
),
agg_base AS (
  -- Aggregate statistics per LOS group
  SELECT
    los_group,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate,
    -- Median time-to-death (for deaths only)
    APPROX_QUANTILES(time_to_death_days, 2)[OFFSET(1)] AS median_time_to_death_days
  FROM los_groups
  WHERE los_group IS NOT NULL
  GROUP BY los_group
)
SELECT
  los_group AS LOS_group,
  n_admissions,
  n_deaths,
  ROUND(mortality_rate * 100, 1) AS mortality_rate_pct,
  -- Wilson score interval for 95% CI (expressed in percent)
  ROUND(
    SAFE_DIVIDE(
      (
        mortality_rate + (POWER(1.96,2)/(2*n_admissions))
        - 1.96 * SQRT(
            (mortality_rate*(1-mortality_rate) + POWER(1.96,2)/(4*n_admissions))
            / n_admissions
          )
      ),
      (1 + POWER(1.96,2)/n_admissions)
    ) * 100
  , 1) AS ci_95_lower_pct,
  ROUND(
    SAFE_DIVIDE(
      (
        mortality_rate + (POWER(1.96,2)/(2*n_admissions))
        + 1.96 * SQRT(
            (mortality_rate*(1-mortality_rate) + POWER(1.96,2)/(4*n_admissions))
            / n_admissions
          )
      ),
      (1 + POWER(1.96,2)/n_admissions)
    ) * 100
  , 1) AS ci_95_upper_pct,
  median_time_to_death_days
FROM agg_base
ORDER BY
  CASE los_group
    WHEN '1-3' THEN 1
    WHEN '4-7' THEN 2
    WHEN '8+' THEN 3
    ELSE 4
  END
;