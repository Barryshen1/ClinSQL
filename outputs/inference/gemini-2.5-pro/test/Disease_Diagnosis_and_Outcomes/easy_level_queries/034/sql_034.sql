WITH sepsis_diagnoses AS (
  -- First, identify all ICD codes related to Sepsis or Septic Shock
  -- This approach captures relevant codes across both ICD-9 and ICD-10 versions.
  SELECT
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    LOWER(long_title) LIKE '%sepsis%' OR LOWER(long_title) LIKE '%septic shock%'
), cohort_admissions AS (
  -- Next, build the cohort of admissions meeting all specified criteria.
  SELECT
    adm.hadm_id,
    -- Calculate hospital length of stay (LOS) in fractional days for accuracy.
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  -- Join to get patient demographic information (gender, age anchors).
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  -- Join to get the diagnoses for the hospital admission.
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  -- Join with our list of sepsis codes to filter for relevant diagnoses.
  INNER JOIN
    sepsis_diagnoses AS s_dx
    ON dx.icd_code = s_dx.icd_code AND dx.icd_version = s_dx.icd_version
  WHERE
    -- Filter 1: Diagnosis must be the primary one (sequence number 1).
    dx.seq_num = 1
    -- Filter 2: Patient must be female.
    AND pat.gender = 'F'
    -- Filter 3: Patient's age at admission must be between 40 and 50.
    AND (
      EXTRACT(
        YEAR
        FROM
          adm.admittime
      ) - pat.anchor_year + pat.anchor_age
    ) BETWEEN 40 AND 50
)
-- Finally, calculate the Interquartile Range (IQR) of the hospital LOS for the cohort.
SELECT
  -- APPROX_QUANTILES(value, 4) returns an array: [min, 25th_pctl, median, 75th_pctl, max].
  -- We subtract the 25th percentile (index 1) from the 75th (index 3).
  APPROX_QUANTILES(los_days, 4) [
  OFFSET
    (3)] - APPROX_QUANTILES(los_days, 4) [
  OFFSET
    (1)] AS hospital_los_iqr
FROM
  cohort_admissions
-- Ensure we only include valid LOS calculations.
WHERE
  los_days IS NOT NULL;