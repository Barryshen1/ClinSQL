WITH filtered_admissions AS (
  SELECT
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.hadm_id = d_icd.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON d_icd.icd_code = d_diag.icd_code
    AND d_icd.icd_version = d_diag.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    d_icd.seq_num = 1
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      LOWER(d_diag.long_title) LIKE '%acute coronary syndrome%'
      OR LOWER(d_diag.long_title) LIKE '%myocardial infarction%'
      OR LOWER(d_diag.long_title) LIKE '%unstable angina%'
      OR LOWER(d_diag.long_title) LIKE '%ischemic heart disease%'
    )
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25
FROM
  filtered_admissions;