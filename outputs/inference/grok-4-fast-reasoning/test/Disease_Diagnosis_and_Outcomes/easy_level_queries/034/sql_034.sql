WITH cohort AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_icd
  ON
    a.hadm_id = diag_icd.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON
    diag_icd.icd_code = d_icd.icd_code
    AND diag_icd.icd_version = d_icd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND diag_icd.seq_num = 1
    AND (LOWER(d_icd.long_title) LIKE '%sepsis%' OR LOWER(d_icd.long_title) LIKE '%septic shock%')
    AND a.dischtime IS NOT NULL
    AND a.hadm_id IS NOT NULL
)
SELECT
  (APPROX_QUANTILES(los_days, 4)[OFFSET(3)] - APPROX_QUANTILES(los_days, 4)[OFFSET(1)]) AS los_iqr_days
FROM
  cohort;