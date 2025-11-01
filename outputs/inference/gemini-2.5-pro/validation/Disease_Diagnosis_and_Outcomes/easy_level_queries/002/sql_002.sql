WITH cohort_los AS (
  -- First, identify the cohort of patients and calculate their hospital length of stay
  SELECT
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code
    AND dx.icd_version = d_dx.icd_version
  WHERE
    -- Filter for male patients aged 52-62
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
    -- Filter for primary diagnosis (seq_num = 1)
    AND dx.seq_num = 1
    -- Filter for diagnoses related to Acute Kidney Injury (AKI)
    AND (
      LOWER(d_dx.long_title) LIKE '%acute kidney failure%'
      OR LOWER(d_dx.long_title) LIKE '%acute kidney injury%'
    )
)
-- Then, calculate the 75th percentile of the length of stay for this cohort
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS hospital_los_p75_days
FROM
  cohort_los;