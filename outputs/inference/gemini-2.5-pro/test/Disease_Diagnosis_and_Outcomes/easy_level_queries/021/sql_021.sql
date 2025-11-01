WITH cohort_diagnoses AS (
  -- First, find all hospital admissions that have diagnoses for BOTH conditions.
  SELECT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
  HAVING
    -- Condition 1: Hemorrhagic Stroke (ICD-9: 430, 431, 432*; ICD-10: I60*, I61*, I62*)
    MAX(CASE
      WHEN (icd_version = 9 AND icd_code IN ('430', '431')) THEN 1
      WHEN (icd_version = 9 AND icd_code LIKE '432%') THEN 1
      WHEN (icd_version = 10 AND icd_code LIKE 'I60%') THEN 1
      WHEN (icd_version = 10 AND icd_code LIKE 'I61%') THEN 1
      WHEN (icd_version = 10 AND icd_code LIKE 'I62%') THEN 1
      ELSE 0
    END) = 1
    AND
    -- Condition 2: COPD Exacerbation (ICD-9: 49121; ICD-10: J441)
    MAX(CASE
      WHEN icd_version = 9 AND icd_code = '49121' THEN 1
      WHEN icd_version = 10 AND icd_code = 'J441' THEN 1
      ELSE 0
    END) = 1
),
cohort_los AS (
  -- Second, filter for patient demographics and calculate LOS for the relevant admissions.
  SELECT
    adm.hadm_id,
    -- Calculate hospital length of stay in fractional days for more precision.
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
  INNER JOIN
    cohort_diagnoses AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    -- Filter for female patients
    p.gender = 'F'
    -- Filter for patients aged 58-68 at the time of admission
    AND (p.anchor_age + EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 58 AND 68
    -- Ensure dischtime and admittime are valid for LOS calculation
    AND adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL
)
-- Finally, calculate the Interquartile Range (IQR) of the hospital LOS.
SELECT
  -- IQR = 75th percentile (Q3) - 25th percentile (Q1)
  -- APPROX_QUANTILES returns an array; we access elements by OFFSET (0-indexed).
  (APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)]) AS hospital_los_iqr
FROM
  cohort_los
WHERE
  -- Exclude admissions with zero or negative LOS
  los_days > 0;