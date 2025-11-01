WITH icd_diagnoses AS (
  -- Step 1: Create flags for relevant ICD codes based on their text descriptions.
  -- This is more efficient than repeated LIKE operations on the larger diagnoses_icd table.
  SELECT
    icd_code,
    icd_version,
    -- Flag any diagnosis containing 'sepsis'
    CASE
      WHEN LOWER(long_title) LIKE '%sepsis%'
      THEN 1
      ELSE 0
    END AS is_sepsis,
    -- Flag any diagnosis containing 'septic shock'
    CASE
      WHEN LOWER(long_title) LIKE '%septic shock%'
      THEN 1
      ELSE 0
    END AS is_septic_shock,
    -- Flag for Chronic Kidney Disease
    CASE
      WHEN LOWER(long_title) LIKE '%chronic kidney disease%' OR LOWER(long_title) LIKE '%chronic renal failure%'
      THEN 1
      ELSE 0
    END AS is_ckd,
    -- Flag for Diabetes, using 'diabetes mellitus' for specificity
    CASE
      WHEN LOWER(long_title) LIKE '%diabetes mellitus%'
      THEN 1
      ELSE 0
    END AS is_diabetes,
    -- Flag for Atrial Fibrillation
    CASE
      WHEN LOWER(long_title) LIKE '%atrial fibrillation%'
      THEN 1
      ELSE 0
    END AS is_afib,
    -- Flag for Hypertension
    CASE
      WHEN LOWER(long_title) LIKE '%hypertension%'
      THEN 1
      ELSE 0
    END AS is_hypertension
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
), hadm_diagnoses AS (
  -- Step 2: Aggregate the diagnosis flags for each hospital admission (hadm_id).
  SELECT
    dia.hadm_id,
    MAX(icd.is_sepsis) AS has_sepsis,
    MAX(icd.is_septic_shock) AS has_septic_shock,
    MAX(icd.is_ckd) AS has_ckd,
    MAX(icd.is_diabetes) AS has_diabetes,
    MAX(icd.is_afib) AS has_afib,
    MAX(icd.is_hypertension) AS has_hypertension
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
  JOIN
    icd_diagnoses AS icd
    ON dia.icd_code = icd.icd_code AND dia.icd_version = icd.icd_version
  GROUP BY
    dia.hadm_id
), base_cohort AS (
  -- Step 3: Define the base patient cohort based on demographics and calculate hospital LOS.
  SELECT
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
)
-- Step 4: Combine, filter, stratify, and aggregate to get the final result.
SELECT
  CASE
    WHEN cohort.los_days <= 5
    THEN '<=5 days'
    ELSE '>5 days'
  END AS los_group,
  dx.has_ckd,
  dx.has_diabetes,
  dx.has_afib,
  dx.has_hypertension,
  COUNT(cohort.hadm_id) AS num_admissions,
  SUM(cohort.hospital_expire_flag) AS num_deaths,
  ROUND(SUM(cohort.hospital_expire_flag) * 100.0 / COUNT(cohort.hadm_id), 2) AS mortality_percent
FROM
  base_cohort AS cohort
JOIN
  hadm_diagnoses AS dx
  ON cohort.hadm_id = dx.hadm_id
WHERE
  dx.has_sepsis = 1
  AND dx.has_septic_shock = 0
  AND cohort.los_days IS NOT NULL -- Exclude admissions without a valid discharge time
GROUP BY
  los_group,
  dx.has_ckd,
  dx.has_diabetes,
  dx.has_afib,
  dx.has_hypertension
ORDER BY
  los_group,
  has_ckd DESC,
  has_diabetes DESC,
  has_afib DESC,
  has_hypertension DESC;