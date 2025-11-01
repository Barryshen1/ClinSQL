SELECT
  APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0, 4)[OFFSET(1)] AS Q1,
  APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0, 4)[OFFSET(3)] AS Q3,
  APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0, 4)[OFFSET(3)] -
    APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0, 4)[OFFSET(1)] AS IQR
FROM
  physionet-data.mimiciv_3_1_hosp.admissions a
JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 84 AND 94
  AND d.seq_num = 1
  AND (
    (d.icd_version = 9 AND d.icd_code = '530.21') OR
    (d.icd_version = 10 AND d.icd_code = 'K92.0')
  )
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;