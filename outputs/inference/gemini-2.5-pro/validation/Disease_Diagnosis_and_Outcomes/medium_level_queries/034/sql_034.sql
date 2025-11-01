WITH hf_admissions AS (
  -- Step 1: Identify all hospital admissions with a heart failure diagnosis
  SELECT DISTINCT
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code
    AND dx.icd_version = d_dx.icd_version
  WHERE
    LOWER(d_dx.long_title) LIKE '%heart failure%'
), cohort_admissions AS (
  -- Step 2: Filter for female patients aged 70-80 at the time of their heart failure admission
  SELECT
    ad.hadm_id,
    ad.admittime,
    ad.dischtime,
    ad.deathtime,
    ad.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ad.subject_id = p.subject_id
  INNER JOIN
    hf_admissions AS hf
    ON ad.hadm_id = hf.hadm_id
  WHERE
    p.gender = 'F'
    -- Calculate age at admission and filter for 70-80 years old
    AND (
      DATETIME_DIFF(ad.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age
    ) BETWEEN 70 AND 80
), metrics AS (
  -- Step 3: Calculate LOS, create LOS groups, and determine time-to-death for each admission
  SELECT
    hadm_id,
    hospital_expire_flag,
    CASE
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) < 8 THEN '<8 days'
      ELSE '>=8 days'
    END AS los_group,
    -- Calculate time to death in days only for non-survivors
    CASE
      WHEN hospital_expire_flag = 1 THEN DATETIME_DIFF(deathtime, admittime, DAY)
      ELSE NULL
    END AS time_to_death_days
  FROM
    cohort_admissions
  -- Ensure LOS can be calculated
  WHERE
    dischtime IS NOT NULL
)
-- Step 4: Aggregate the metrics by LOS group to get the final results
SELECT
  los_group,
  COUNT(hadm_id) AS admission_count,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_percent,
  -- Calculate the median time to death for non-survivors (APPROX_QUANTILES ignores NULLs)
  ROUND(APPROX_QUANTILES(time_to_death_days, 100)[OFFSET(50)], 1) AS median_time_to_death_days
FROM
  metrics
GROUP BY
  los_group
ORDER BY
  los_group;