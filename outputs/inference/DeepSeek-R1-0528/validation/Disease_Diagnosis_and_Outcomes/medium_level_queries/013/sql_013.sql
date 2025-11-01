WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_admit,
    -- Calculate LOS in days
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  -- Filter for heart failure diagnosis
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    WHERE adm.hadm_id = diag.hadm_id
      AND (
        (diag.icd_version = 9 AND diag.icd_code LIKE '428%') OR
        (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
      )
  )
    AND p.gender = 'F'
    -- Age 80-90 at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 80 AND 90
),

cohort_with_group AS (
  SELECT *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
    END AS los_group
  FROM cohort
  -- Exclude same-day discharges (LOS=0)
  WHERE los_days >= 1
),

-- Calculate median time-to-death per group (de-correlated)
deceased_median AS (
  SELECT
    los_group,
    APPROX_QUANTILES(
      TIMESTAMP_DIFF(deathtime, admittime, HOUR) / 24.0, 
      100
    )[OFFSET(50)] AS median_time_to_death_days
  FROM cohort_with_group
  WHERE hospital_expire_flag = 1
  GROUP BY los_group
),

aggregated AS (
  SELECT
    los_group,
    COUNT(*) AS total_admissions,
    SUM(hospital_expire_flag) AS n_deaths,
    -- Mortality proportion
    SUM(hospital_expire_flag) / COUNT(*) AS mortality_proportion
  FROM cohort_with_group
  GROUP BY los_group
)

SELECT
  a.los_group,
  a.total_admissions,
  a.n_deaths,
  -- Mortality percentage
  ROUND(a.mortality_proportion * 100, 2) AS mortality_percentage,
  -- 95% CI (capped at 0 and 100)
  ROUND(
    GREATEST(0, 
      (a.mortality_proportion - 1.96 * SQRT(a.mortality_proportion * (1 - a.mortality_proportion) / a.total_admissions)) * 100
    ), 2
  ) AS mortality_95_ci_lower,
  ROUND(
    LEAST(100,
      (a.mortality_proportion + 1.96 * SQRT(a.mortality_proportion * (1 - a.mortality_proportion) / a.total_admissions)) * 100
    ), 2
  ) AS mortality_95_ci_upper,
  -- Median time-to-death (days, for deceased patients)
  d.median_time_to_death_days
FROM aggregated a
LEFT JOIN deceased_median d
  ON a.los_group = d.los_group
ORDER BY
  CASE a.los_group
    WHEN '1-3' THEN 1
    WHEN '4-7' THEN 2
    WHEN '>=8' THEN 3
  END;