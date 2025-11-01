WITH aki_admissions AS (
  -- First, identify all hospital admissions for female patients aged 48-58 with a diagnosis of AKI.
  SELECT DISTINCT
    dx.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON pat.subject_id = dx.subject_id
  WHERE
    -- Filter for female patients between 48 and 58 years old.
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 48 AND 58
    -- Filter for diagnoses of Acute Kidney Injury (AKI) or Acute Renal Failure (ARF).
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '584%') -- ICD-9 for Acute Renal Failure
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%') -- ICD-10 for Acute Kidney Injury
    )
)
-- Now, calculate the 25th percentile ICU length of stay for these admissions.
SELECT
  APPROX_QUANTILES(icu.los, 4)[OFFSET(1)] AS los_25th_percentile_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
INNER JOIN aki_admissions AS aki
  ON icu.hadm_id = aki.hadm_id
-- The join ensures we only consider ICU stays for the specified patient cohort.
-- The APPROX_QUANTILES function then calculates the 25th percentile of the 'los' (in days) for these stays.;