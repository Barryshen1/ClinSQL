WITH
-- Cohort: Female 44-54 with ICH
ich_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    -- 90-day mortality: death within 90 days of admission
    CASE
      WHEN DATETIME_DIFF(COALESCE(a.deathtime, p.dod), a.admittime, DAY) <= 90 THEN 1
      ELSE 0
    END AS mortality_90day,
    -- LOS for survivors
    CASE
      WHEN a.hospital_expire_flag = 0 THEN DATETIME_DIFF(a.dischtime, a.admittime, DAY)
      ELSE NULL
    END AS los_survivor,
    -- Identify severe sepsis (ICD-9: 995.92, ICD-10: R65.20, R65.21)
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code = '99592')
          OR (di.icd_version = 10 AND di.icd_code IN ('R6520', 'R6521'))
        )
    ) AS has_severe_sepsis
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          -- ICD-10 codes
          dd.long_title LIKE '%intracranial hemorrhage%'
          OR dd.long_title LIKE '%intracerebral hemorrhage%'
          OR dd.long_title LIKE '%subarachnoid hemorrhage%'
          OR dd.long_title LIKE '%subdural hemorrhage%'
          OR dd.long_title LIKE '%extradural hemorrhage%'
          -- ICD-9 codes
          OR dd.long_title LIKE '%intracranial hemorrhage%'
          OR dd.long_title LIKE '%intracerebral hemorrhage%'
          OR dd.long_title LIKE '%subarachnoid hemorrhage%'
          OR dd.long_title LIKE '%subdural hemorrhage%'
          OR dd.long_title LIKE '%extradural hemorrhage%'
        )
    )
),

-- Control group: Female 44-54 without ICH
control_group AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    -- LOS for survivors
    CASE
      WHEN a.hospital_expire_flag = 0 THEN DATETIME_DIFF(a.dischtime, a.admittime, DAY)
      ELSE NULL
    END AS los_survivor,
    -- Severe sepsis
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code = '99592')
          OR (di.icd_version = 10 AND di.icd_code IN ('R6520', 'R6521'))
        )
    ) AS has_severe_sepsis
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          dd.long_title LIKE '%intracranial hemorrhage%'
          OR dd.long_title LIKE '%intracerebral hemorrhage%'
          OR dd.long_title LIKE '%subarachnoid hemorrhage%'
          OR dd.long_title LIKE '%subdural hemorrhage%'
          OR dd.long_title LIKE '%extradural hemorrhage%'
        )
    )
)

-- Main results
SELECT
  'ICH Cohort' AS cohort,
  COUNT(*) AS n_patients,
  -- Median and IQR for LOS (survivors only)
  APPROX_QUANTILES(los_survivor, 100) [OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_survivor, 100) [OFFSET(25)] AS q1_los,
  APPROX_QUANTILES(los_survivor, 100) [OFFSET(75)] AS q3_los,
  -- 90-day mortality rate
  AVG(mortality_90day) * 100 AS mortality_90day_percent,
  -- Severe sepsis rate
  AVG(CAST(has_severe_sepsis AS INT)) * 100 AS severe_sepsis_percent
FROM ich_cohort
WHERE los_survivor IS NOT NULL  -- Only survivors for LOS

UNION ALL

SELECT
  'Control Group' AS cohort,
  COUNT(*) AS n_patients,
  APPROX_QUANTILES(los_survivor, 100) [OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_survivor, 100) [OFFSET(25)] AS q1_los,
  APPROX_QUANTILES(los_survivor, 100) [OFFSET(75)] AS q3_los,
  NULL AS mortality_90day_percent,  -- Not computed for control
  AVG(CAST(has_severe_sepsis AS INT)) * 100 AS severe_sepsis_percent
FROM control_group
WHERE los_survivor IS NOT NULL;