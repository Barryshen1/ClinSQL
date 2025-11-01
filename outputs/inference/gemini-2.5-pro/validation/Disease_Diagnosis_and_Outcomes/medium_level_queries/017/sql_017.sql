WITH
  -- Step 1: Identify hospital admissions (hadm_id) with a diagnosis of sepsis
  -- but explicitly NOT septic shock. This requires checking both ICD-9 and ICD-10 codes.
  sepsis_admissions AS (
    SELECT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
    HAVING
      -- Condition 1: Must have at least one sepsis diagnosis code
      COUNTIF(
        (
          icd_version = 9 AND icd_code = '99591'
        ) -- Sepsis in ICD-9
        OR (
          icd_version = 10 AND STARTS_WITH(icd_code, 'A41')
        ) -- Sepsis in ICD-10 (e.g., A41.9)
      ) > 0
      AND
      -- Condition 2: Must NOT have any septic shock diagnosis codes
      COUNTIF(
        (
          icd_version = 9 AND icd_code = '78552'
        ) -- Septic shock in ICD-9
        OR (
          icd_version = 10 AND icd_code = 'R6521'
        ) -- Severe sepsis with septic shock in ICD-10
      ) = 0
  ),
  -- Step 2: Filter for the patient cohort: males, aged 50-60, with a sepsis admission.
  -- Calculate hospital LOS and create the LOS group category.
  cohort AS (
    SELECT
      adm.hadm_id,
      adm.hospital_expire_flag,
      adm.admittime,
      adm.deathtime,
      CASE
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) < 8
        THEN '< 8 days'
        ELSE '>= 8 days'
      END AS los_group
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON adm.subject_id = pat.subject_id
    INNER JOIN
      sepsis_admissions AS sep ON adm.hadm_id = sep.hadm_id
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 50 AND 60
  )
-- Step 3: Group by the LOS category and calculate the final metrics.
SELECT
  los_group,
  -- In-hospital mortality as a percentage
  100.0 * AVG(cohort.hospital_expire_flag) AS mortality_percentage,
  -- 95% CI for mortality using the normal approximation (Wald interval)
  -- CI = p ± 1.96 * sqrt(p * (1 - p) / n)
  GREATEST(
    0, 100.0 * (
      AVG(cohort.hospital_expire_flag) - 1.96 * SQRT(
        AVG(cohort.hospital_expire_flag) * (
          1 - AVG(cohort.hospital_expire_flag)
        ) / COUNT(cohort.hadm_id)
      )
    )
  ) AS mortality_ci_95_lower,
  LEAST(
    100, 100.0 * (
      AVG(cohort.hospital_expire_flag) + 1.96 * SQRT(
        AVG(cohort.hospital_expire_flag) * (
          1 - AVG(cohort.hospital_expire_flag)
        ) / COUNT(cohort.hadm_id)
      )
    )
  ) AS mortality_ci_95_upper,
  -- Median time to death in days for non-survivors
  APPROX_QUANTILES(
    CASE
      WHEN cohort.hospital_expire_flag = 1
      THEN DATETIME_DIFF(cohort.deathtime, cohort.admittime, DAY)
      ELSE NULL
    END,
    2
  ) [
  OFFSET
    (1)] AS median_time_to_death_days
FROM cohort
GROUP BY
  los_group
ORDER BY
  los_group;