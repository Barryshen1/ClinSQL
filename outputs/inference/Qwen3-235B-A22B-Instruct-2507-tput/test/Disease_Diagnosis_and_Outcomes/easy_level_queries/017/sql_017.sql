SELECT
  MAX(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS max_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp`.patients pat
JOIN
  `physionet-data.mimiciv_3_1_hosp`.admissions adm
  ON pat.subject_id = adm.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
  ON adm.hadm_id = diag.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
  ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
WHERE
  pat.gender = 'M'
  AND d_diag.icd_version = 10
  AND d_diag.icd_code LIKE 'I63%'
  AND diag.seq_num = 1
  AND adm.dischtime IS NOT NULL
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 84 AND 94;