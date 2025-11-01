SELECT
  APPROX_QUANTILES(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY), 2)[OFFSET(1)] AS median_los_days
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
  AND pat.anchor_age BETWEEN 59 AND 69
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code IN ('43491', '43391', '43411', '43401'))
    OR
    (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
  )
  AND adm.dischtime > adm.admittime;