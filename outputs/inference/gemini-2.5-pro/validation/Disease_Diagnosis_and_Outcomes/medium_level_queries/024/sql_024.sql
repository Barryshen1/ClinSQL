WITH
-- Step 1: Identify the base patient cohort of females aged 49-59
patient_cohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
),

-- Step 2: For each hospital admission, flag relevant diagnoses (Sepsis, Septic Shock, CKD, Diabetes)
hadm_diagnoses_flags AS (
  SELECT
    diag.hadm_id,
    MAX(CASE WHEN LOWER(d_icd.long_title) LIKE '%sepsis%' THEN 1 ELSE 0 END) AS has_sepsis,
    MAX(CASE WHEN LOWER(d_icd.long_title) LIKE '%septic shock%' THEN 1 ELSE 0 END) AS has_septic_shock,
    MAX(CASE WHEN LOWER(d_icd.long_title) LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN LOWER(d_icd.long_title) LIKE '%diabetes mellitus%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE
    diag.subject_id IN (SELECT subject_id FROM patient_cohort)
  GROUP BY
    diag.hadm_id
),

-- Step 3: Filter for the final cohort: Sepsis without Septic Shock
sepsis_cohort AS (
  SELECT
    hadm_id,
    has_ckd,
    has_diabetes
  FROM
    hadm_diagnoses_flags
  WHERE
    has_sepsis = 1
    AND has_septic_shock = 0
),

-- Step 4: Identify hospital admissions that had an ICU stay within the first 24 hours
day1_icu_hadms AS (
  SELECT DISTINCT
    icu.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  WHERE
    DATETIME_DIFF(icu.intime, adm.admittime, HOUR) <= 24
),

-- Step 5: Combine the cohort with admission data and stratification flags
cohort_with_strata AS (
  SELECT
    sc.hadm_id,
    adm.hospital_expire_flag,
    sc.has_ckd,
    sc.has_diabetes,
    -- Stratification 1: Hospital Length of Stay (LOS)
    CASE
      WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) <= 5 THEN 'LOS <= 5 days'
      ELSE 'LOS > 5 days'
    END AS los_group,
    -- Stratification 2: Day-1 ICU Admission
    CASE
      WHEN d1_icu.hadm_id IS NOT NULL THEN 'Day-1 ICU'
      ELSE 'Non-Day-1 ICU'
    END AS icu_group
  FROM
    sepsis_cohort AS sc
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON sc.hadm_id = adm.hadm_id
  LEFT JOIN
    day1_icu_hadms AS d1_icu
    ON sc.hadm_id = d1_icu.hadm_id
)

-- Final Step: Aggregate by the strata and calculate the required metrics
SELECT
  cws.los_group,
  cws.icu_group,
  COUNT(DISTINCT cws.hadm_id) AS N,
  ROUND(AVG(cws.hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(cws.has_ckd) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(cws.has_diabetes) * 100, 2) AS diabetes_prevalence_pct
FROM
  cohort_with_strata AS cws
GROUP BY
  cws.los_group,
  cws.icu_group
ORDER BY
  cws.los_group,
  cws.icu_group;