WITH cohort_admissions AS (
  -- First, identify all hospital admissions (hadm_id) that match the cohort criteria.
  SELECT DISTINCT
    diag.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON pat.subject_id = diag.subject_id
  WHERE
    -- 1. Filter for male patients aged 81-91
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 81 AND 91
    -- 2. Filter for primary diagnoses (seq_num = 1)
    AND diag.seq_num = 1
    -- 3. Filter for Acute Kidney Injury using both ICD-9 and ICD-10 codes
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '584%') -- ICD-9 for Acute renal failure
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%') -- ICD-10 for Acute kidney injury
    )
)
-- Now, calculate the IQR of hospital length of stay for this cohort.
SELECT
  -- The APPROX_QUANTILES function returns an array: [min, 25th, 50th, 75th, max].
  -- We subtract the 25th percentile (index 1) from the 75th (index 3).
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS hospital_los_iqr_days
FROM (
  SELECT
    APPROX_QUANTILES(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY), 4) AS quantiles
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    cohort_admissions
    ON adm.hadm_id = cohort_admissions.hadm_id
  WHERE
    -- Ensure the discharge and admission times are valid to calculate LOS.
    adm.dischtime IS NOT NULL
    AND adm.admittime IS NOT NULL
    -- Exclude any records with negative length of stay due to data errors.
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) >= 0
);