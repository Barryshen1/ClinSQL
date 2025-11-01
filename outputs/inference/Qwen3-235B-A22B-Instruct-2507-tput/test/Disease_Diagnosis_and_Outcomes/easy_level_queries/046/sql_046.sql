SELECT
  STDDEV(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY)) AS hospital_los_sd_days
FROM
  `physionet-data.mimiciv_3_1_hosp`.admissions adm
JOIN
  `physionet-data.mimiciv_3_1_hosp`.patients pat
  ON adm.subject_id = pat.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
  ON adm.hadm_id = diag.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
  ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
WHERE
  pat.gender = 'M'
  AND diag.seq_num = 1  -- primary diagnosis
  AND (
    (diag.icd_version = 10 AND (d_diag.icd_code LIKE 'I61%' OR d_diag.icd_code LIKE 'I62%'))
    OR
    (diag.icd_version = 9 AND (d_diag.icd_code = '431' OR d_diag.icd_code = '432'))
  )
  AND (
    EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age)
  ) BETWEEN 43 AND 53
  AND adm.admittime IS NOT NULL
  AND adm.dischtime IS NOT NULL;