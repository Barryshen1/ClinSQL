SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS hospital_los_75th_percentile
FROM (
  SELECT
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
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
    AND diag.seq_num = 1  -- primary diagnosis
    AND (
      (diag.icd_version = 9 AND diag.icd_code = '431')  -- ICD-9: intracerebral hemorrhage
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I61%')  -- ICD-10: intracerebral hemorrhage
    )
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 37 AND 47
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)
WHERE
  los_days >= 0;