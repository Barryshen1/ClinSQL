WITH CohortAdmissions AS (
  SELECT DISTINCT -- Use DISTINCT to ensure each hospital admission is counted only once
    a.hadm_id,
    -- Calculate length of stay in fractional days for precision
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON a.hadm_id = dx.hadm_id
  WHERE
    -- 1. Filter for female patients aged 49-59
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    -- 2. Filter for primary diagnosis of COPD exacerbation
    AND dx.seq_num = 1
    AND (
      -- ICD-9 code for Obstructive chronic bronchitis with acute exacerbation
      (dx.icd_code = '49121' AND dx.icd_version = 9)
      -- ICD-10 code for Chronic obstructive pulmonary disease with acute exacerbation
      OR (dx.icd_code = 'J441' AND dx.icd_version = 10)
    )
)
-- 3. Calculate the 25th percentile of hospital LOS for the cohort
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_25th_percentile_days
FROM CohortAdmissions
-- Filter out admissions where discharge time is not available
WHERE los_days IS NOT NULL;