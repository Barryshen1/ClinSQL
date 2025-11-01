WITH
-- Step 1: Identify the cohort of hospital admissions based on patient demographics and admission diagnosis.
-- The cohort consists of male patients aged 67-77 admitted with a diagnosis of heart failure.
admissions_cohort AS (
  SELECT DISTINCT
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
  INNER JOIN
    -- Join to diagnoses to filter for heart failure
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    -- Filter for male patients
    p.gender = 'M'
    -- Filter for age at admission between 67 and 77
    AND (DATETIME_DIFF(adm.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) BETWEEN 67 AND 77
    -- Filter for heart failure diagnosis codes (ICD-9: 428.xx, ICD-10: I50.xx)
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
    )
),

-- Step 2: For each admission in the cohort, generate the stratification variables and outcome flags.
hadm_features AS (
  SELECT
    c.hadm_id,
    c.hospital_expire_flag,

    -- Stratification 1: Categorize hospital length of stay (LOS)
    CASE
      WHEN DATETIME_DIFF(c.dischtime, c.admittime, DAY) <= 7 THEN '<=7 days'
      ELSE '>7 days'
    END AS los_category,

    -- Stratification 2: Determine if the patient was admitted to ICU on Day 1
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        WHERE icu.hadm_id = c.hadm_id
          AND icu.intime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
      ) THEN 'ICU Day 1'
      ELSE 'No ICU Day 1'
    END AS day1_icu_status,

    -- Outcome flag for Chronic Kidney Disease (CKD)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx_ckd
        WHERE dx_ckd.hadm_id = c.hadm_id
          AND (
            (dx_ckd.icd_version = 9 AND dx_ckd.icd_code LIKE '585%')
            OR (dx_ckd.icd_version = 10 AND dx_ckd.icd_code LIKE 'N18%')
          )
      ) THEN 1
      ELSE 0
    END AS has_ckd,

    -- Outcome flag for Diabetes
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx_diab
        WHERE dx_diab.hadm_id = c.hadm_id
          AND (
            (dx_diab.icd_version = 9 AND dx_diab.icd_code LIKE '250%')
            OR (dx_diab.icd_version = 10 AND SUBSTR(dx_diab.icd_code, 1, 3) IN ('E08', 'E09', 'E10', 'E11', 'E13'))
          )
      ) THEN 1
      ELSE 0
    END AS has_diabetes
  FROM
    admissions_cohort AS c
)

-- Step 3: Aggregate the features to calculate final metrics, grouped by the stratification variables.
SELECT
  los_category,
  day1_icu_status,
  COUNT(hadm_id) AS number_of_admissions,
  -- Calculate percentages by taking the average of the 0/1 flags
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_pct
FROM
  hadm_features
GROUP BY
  los_category,
  day1_icu_status
ORDER BY
  los_category,
  day1_icu_status;