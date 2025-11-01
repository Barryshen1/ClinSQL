SELECT
  PERCENTILE_CONT(los_days, 0.25) WITHIN GROUP (ORDER BY los_days) AS los_25th_percentile
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
    p.gender = 'M'
    AND diag.seq_num = 1  -- primary diagnosis
    AND (
      (d_diag.icd_version = 9 AND d_diag.icd_code IN ('5780', '5781'))
      OR (d_diag.icd_version = 10 AND d_diag.icd_code IN ('K920', 'K921', 'K922'))
    )
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 74 AND 84
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)
WHERE
  los_days >= 0;