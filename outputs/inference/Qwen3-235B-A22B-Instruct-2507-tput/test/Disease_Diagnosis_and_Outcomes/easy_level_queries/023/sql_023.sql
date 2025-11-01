SELECT
  APPROX_QUANTILES(los_hospital_days, 2)[OFFSET(1)] AS median_los_days
FROM (
  SELECT
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 3600) AS los_hospital_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON
    a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
  ON
    diag.icd_code = d_diag.icd_code
    AND diag.icd_version = d_diag.icd_version
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 83 AND 93
    AND diag.seq_num = 1
    AND LOWER(d_diag.long_title) LIKE '%pneumonia%'
    AND LOWER(d_diag.long_title) LIKE '%community%'
    AND a.dischtime IS NOT NULL
);