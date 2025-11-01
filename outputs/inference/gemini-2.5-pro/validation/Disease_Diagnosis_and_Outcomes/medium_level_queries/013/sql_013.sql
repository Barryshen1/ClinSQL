WITH
  -- Step 1: Identify all hospital admissions with a diagnosis of Heart Failure (HF)
  hf_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for Heart Failure start with '428'
      SUBSTR(icd_code, 1, 3) = '428'
      -- ICD-10 codes for Heart Failure start with 'I50'
      OR SUBSTR(icd_code, 1, 3) = 'I50'
  ),

  -- Step 2: Define the patient cohort: women, aged 80-90, with an HF admission.
  -- Calculate LOS and time-to-death for each admission.
  cohort_data AS (
    SELECT
      adm.hadm_id,
      adm.hospital_expire_flag,
      -- Calculate Length of Stay (LOS) in days.
      -- CEIL rounds up to the nearest day. GREATEST ensures a minimum of 1 day.
      GREATEST(1, CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0)) AS los_days,
      -- Calculate time to death in days only for those who died in-hospital
      CASE
        WHEN adm.hospital_expire_flag = 1
        THEN DATETIME_DIFF(adm.deathtime, adm.admittime, DAY)
        ELSE NULL
      END AS time_to_death_days
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN hf_admissions AS hf
      ON adm.hadm_id = hf.hadm_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 80 AND 90
      -- Ensure dischtime exists to allow for LOS calculation
      AND adm.dischtime IS NOT NULL
  ),

  -- Step 3: Assign each admission to a Length of Stay (LOS) group
  los_grouped_data AS (
    SELECT
      hadm_id,
      hospital_expire_flag,
      time_to_death_days,
      CASE
        WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
        WHEN los_days >= 8 THEN '>=8 days'
        ELSE NULL -- This case should not be reached due to the GREATEST(1,...) above
      END AS los_group
    FROM
      cohort_data
  ),

  -- Step 4: Calculate aggregate statistics per LOS group
  final_stats AS (
    SELECT
      los_group,
      COUNT(hadm_id) AS total_admissions,
      SUM(hospital_expire_flag) AS deceased_admissions,
      -- Use APPROX_QUANTILES to find the median (50th percentile) of time to death
      APPROX_QUANTILES(time_to_death_days, 100)[OFFSET(50)] AS median_time_to_death_days
    FROM
      los_grouped_data
    WHERE
      los_group IS NOT NULL
    GROUP BY
      los_group
  )

-- Step 5: Final presentation with mortality rate and 95% CI
SELECT
  s.los_group,
  -- Calculate mortality rate and 95% CI using the normal approximation method
  -- CI formula: p ± 1.96 * sqrt(p * (1-p) / n)
  SAFE_DIVIDE(s.deceased_admissions, s.total_admissions) * 100 AS mortality_percent,
  (
    SAFE_DIVIDE(s.deceased_admissions, s.total_admissions) - 1.96 * SQRT(
      SAFE_DIVIDE(
        (SAFE_DIVIDE(s.deceased_admissions, s.total_admissions) * (1 - SAFE_DIVIDE(s.deceased_admissions, s.total_admissions))),
        s.total_admissions
      )
    )
  ) * 100 AS mortality_ci95_lower,
  (
    SAFE_DIVIDE(s.deceased_admissions, s.total_admissions) + 1.96 * SQRT(
      SAFE_DIVIDE(
        (SAFE_DIVIDE(s.deceased_admissions, s.total_admissions) * (1 - SAFE_DIVIDE(s.deceased_admissions, s.total_admissions))),
        s.total_admissions
      )
    )
  ) * 100 AS mortality_ci95_upper,
  s.median_time_to_death_days
FROM
  final_stats AS s
ORDER BY
  -- Order the LOS groups logically for readability
  CASE
    WHEN s.los_group = '1-3 days' THEN 1
    WHEN s.los_group = '4-7 days' THEN 2
    WHEN s.los_group = '>=8 days' THEN 3
  END;