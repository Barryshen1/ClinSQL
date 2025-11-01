WITH cohort_los AS (
  SELECT DISTINCT
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
    ON diag.icd_code = d_diag.icd_code
    AND diag.icd_version = d_diag.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND LOWER(d_diag.long_title) LIKE '%pneumonia%'
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_days_25th_percentile
FROM
  cohort_los
WHERE
  los_days >= 0;