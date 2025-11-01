SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS hospital_los_25th_percentile
FROM (
  SELECT
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 3600) AS los_days
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
    diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    p.gender = 'F'
    AND diag.seq_num = 1  -- primary diagnosis
    AND diag.icd_version = 10
    AND LOWER(d_diag.long_title) LIKE '%cerebral infarction%'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 50 AND 60
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
WHERE
  los_days >= 0;