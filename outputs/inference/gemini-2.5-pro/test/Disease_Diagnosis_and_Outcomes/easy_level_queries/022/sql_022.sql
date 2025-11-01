WITH cohort_los AS (
  SELECT
    -- Calculate hospital LOS in days for each qualifying admission
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    -- 1. Patient cohort filters: females aged 71-81
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 71 AND 81
    -- 2. Primary diagnosis filter
    AND dx.seq_num = 1
    -- 3. Ischemic stroke diagnosis filter (across ICD-9 and ICD-10)
    AND (
      LOWER(d_dx.long_title) LIKE '%ischemic stroke%'
      OR LOWER(d_dx.long_title) LIKE '%cerebral infarction%'
    )
)
SELECT
  -- Calculate the Interquartile Range (Q3 - Q1) of the hospital LOS.
  -- APPROX_QUANTILES(expression, 4) returns an array: [min, Q1, median, Q3, max]
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] - APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS iqr_los_days
FROM cohort_los
WHERE
  -- Ensure LOS is a valid, non-negative number before calculating quantiles
  los_days IS NOT NULL AND los_days >= 0;