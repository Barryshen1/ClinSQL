SELECT STDDEV(DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / (24*60*60.0)) AS hospital_los_sd_days
FROM `physionet-data.mimiciv_3_1_hosp`.admissions adm
JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
  ON adm.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
  ON adm.hadm_id = diag.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
  ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
WHERE p.gender = 'M'
  AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 45 AND 55
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 9 AND diag.icd_code = '431')
    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I61%')
  )
  AND adm.admittime IS NOT NULL
  AND adm.dischtime IS NOT NULL;