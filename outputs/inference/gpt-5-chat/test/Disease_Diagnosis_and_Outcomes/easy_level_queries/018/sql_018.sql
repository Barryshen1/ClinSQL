WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
    AND adm.subject_id = diag.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 45 AND 55
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND (
         diag.icd_code = '430'
         OR diag.icd_code = '431'
         OR diag.icd_code LIKE '432%'))
      OR
      (diag.icd_version = 10 AND (
         diag.icd_code LIKE 'I60%'
         OR diag.icd_code LIKE 'I61%'
         OR diag.icd_code LIKE 'I62%'))
    )
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  STDDEV_POP(los_days) AS sd_hospital_los_days
FROM
  cohort;