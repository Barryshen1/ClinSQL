SELECT
  STDDEV_SAMP(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS los_sd_days
FROM
  physionet-data.mimiciv_3_1_hosp.patients pat
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions adm
  ON pat.subject_id = adm.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
  ON adm.hadm_id = diag.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_diag
  ON diag.icd_code = d_diag.icd_code
  AND diag.icd_version = d_diag.icd_version
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 67 AND 77
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code IN ('995.91', '995.92', '785.52'))
    OR
    (diag.icd_version = 10 AND diag.icd_code IN ('A41.9', 'A41.81', 'R65.20', 'R65.21'))
  )
  AND adm.admittime IS NOT NULL
  AND adm.dischtime IS NOT NULL
  AND adm.dischtime > adm.admittime;