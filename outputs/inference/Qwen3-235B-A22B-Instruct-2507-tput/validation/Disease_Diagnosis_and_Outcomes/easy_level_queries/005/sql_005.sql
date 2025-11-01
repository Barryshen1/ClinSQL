SELECT
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days
FROM (
  SELECT
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON
    adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'F'
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '434.%1')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
    )
    AND adm.dischtime IS NOT NULL
    AND adm.admittime <= adm.dischtime
    AND (
      pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year
    ) BETWEEN 59 AND 69
);