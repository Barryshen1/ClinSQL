WITH
  -- Step 1: Identify hospital admissions for the target cohort and calculate their Length of Stay (LOS).
  -- Cohort: Women aged 40-50 with a primary diagnosis of Ischemic Heart Disease (IHD) or Acute Coronary Syndrome (ACS).
  target_admissions AS (
    SELECT
      adm.hadm_id,
      -- Calculate the hospital LOS in days.
      DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON pat.subject_id = adm.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      -- Filter for female patients between 40 and 50 years old.
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 40 AND 50
      -- Filter for the primary diagnosis.
      AND dx.seq_num = 1
      -- Filter for ICD codes corresponding to IHD/ACS.
      -- ICD-9: 410-414 (Ischemic heart disease)
      -- ICD-10: I20-I25 (Ischaemic heart diseases)
      AND (
        (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '410' AND '414')
        OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'I20' AND 'I25')
      )
  )
-- Step 2: From the cohort's admissions, calculate the 25th percentile of the LOS.
SELECT
  -- APPROX_QUANTILES(value, 100) returns an array of 101 values representing the boundaries of 100 percentiles.
  -- OFFSET(25) retrieves the 25th percentile value.
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_25th_percentile_days
FROM
  -- Use DISTINCT to ensure each admission is counted only once for the percentile calculation.
  (SELECT DISTINCT hadm_id, los_days FROM target_admissions);