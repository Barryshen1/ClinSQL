WITH
  -- Step 1: Define the base population (men, aged 69-79) and calculate LOS
  base_admissions AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.hospital_expire_flag,
      a.discharge_location,
      -- Calculate LOS in days, rounding up. A stay of a few hours is counted as 1 day.
      CEIL(
        TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0
      ) AS los_days
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 69 AND 79
      AND a.dischtime IS NOT NULL AND a.admittime IS NOT NULL
  ),
  -- Step 2: Identify hospital admissions with an AMI diagnosis
  ami_hadm AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for AMI
      (
        icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '410'
      )
      -- ICD-10 codes for AMI
      OR (
        icd_version = 10 AND (SUBSTR(icd_code, 1, 3) = 'I21' OR SUBSTR(icd_code, 1, 3) = 'I22')
      )
  ),
  -- Step 3: Identify hospital admissions with exclusion diagnoses (shock or respiratory failure)
  exclusion_hadm AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 exclusion codes
      (
        icd_version = 9
        AND (
          SUBSTR(icd_code, 1, 4) = '7855'  -- Shock
          OR icd_code IN ('51881', '51882', '51884') -- Acute Respiratory Failure
        )
      )
      -- ICD-10 exclusion codes
      OR (
        icd_version = 10
        AND (
          SUBSTR(icd_code, 1, 3) = 'R57'  -- Shock
          OR SUBSTR(icd_code, 1, 3) = 'J96'  -- Respiratory Failure
        )
      )
  ),
  -- Step 4: Build the final cohort by applying inclusion/exclusion criteria and bucketing LOS
  final_cohort AS (
    SELECT
      b.hadm_id,
      b.hospital_expire_flag,
      b.discharge_location,
      b.los_days,
      CASE
        WHEN b.los_days BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN b.los_days BETWEEN 4 AND 7 THEN '4-7 days'
        WHEN b.los_days >= 8 THEN '>=8 days'
        ELSE NULL
      END AS los_group
    FROM
      base_admissions AS b
    -- Include only admissions with an AMI diagnosis
    INNER JOIN
      ami_hadm AS a
      ON b.hadm_id = a.hadm_id
    -- Exclude admissions with shock or respiratory failure
    LEFT JOIN
      exclusion_hadm AS e
      ON b.hadm_id = e.hadm_id
    WHERE
      e.hadm_id IS NULL
  )
-- Step 5: Aggregate results by LOS group and calculate final metrics
SELECT
  los_group,
  COUNT(hadm_id) AS number_of_admissions,
  -- Calculate in-hospital mortality rate, handling potential division by zero
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(hadm_id)) * 100 AS mortality_percent,
  -- Calculate median LOS for the group
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  -- Show top 5 discharge locations and their counts for each group
  APPROX_TOP_COUNT(discharge_location, 5) AS top_discharge_locations
FROM
  final_cohort
WHERE
  los_group IS NOT NULL -- Exclude patients who do not fall into the specified LOS buckets (e.g., LOS < 1 day)
GROUP BY
  los_group
ORDER BY
  -- Order the groups logically by length of stay
  MIN(los_days);