WITH sepsis_admissions AS (
  -- First, identify all hospital admissions (hadm_id) with a diagnosis of sepsis.
  -- Using DISTINCT to avoid duplicates that could arise from multiple sepsis-related
  -- diagnosis codes for the same admission.
  SELECT DISTINCT
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code
    AND dx.icd_version = d_dx.icd_version
  WHERE
    LOWER(d_dx.long_title) LIKE '%sepsis%'
)
-- Main query to filter patients and calculate the median ICU LOS
SELECT
  -- Calculate the median (50th percentile) of the ICU length of stay in days.
  -- APPROX_QUANTILES is the standard aggregate function for percentiles in BigQuery.
  -- APPROX_QUANTILES(icu.los, 2) returns an array: [min, median, max]. [OFFSET(1)] selects the median.
  APPROX_QUANTILES(icu.los, 2)[OFFSET(1)] AS median_icu_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON p.subject_id = adm.subject_id
INNER JOIN
  sepsis_admissions AS sa
  ON adm.hadm_id = sa.hadm_id
INNER JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  ON adm.hadm_id = icu.hadm_id
WHERE
  -- Filter for female patients between 58 and 68 years old.
  p.gender = 'F'
  AND p.anchor_age BETWEEN 58 AND 68;