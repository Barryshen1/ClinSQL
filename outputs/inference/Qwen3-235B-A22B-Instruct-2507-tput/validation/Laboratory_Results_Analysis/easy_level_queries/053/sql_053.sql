SELECT
  APPROX_QUANTILES(l.valuenum, 1000)[OFFSET(750)] AS glucose_75th_percentile_mgdl
FROM
  `physionet-data.mimiciv_3_1_hosp`.patients p
JOIN
  `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
  ON a.hadm_id = diag.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
  ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
JOIN
  `physionet-data.mimiciv_3_1_hosp`.labevents l
  ON a.hadm_id = l.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp`.d_labitems d_lab
  ON l.itemid = d_lab.itemid
WHERE
  p.anchor_age = 82
  AND p.gender = 'F'
  AND d_diag.icd_version = 10
  AND d_diag.icd_code LIKE 'I63%'
  AND LOWER(d_lab.label) = 'glucose'
  AND LOWER(d_lab.fluid) = 'blood'
  AND l.charttime >= a.admittime
  AND l.charttime <= DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
  AND l.valuenum IS NOT NULL
  AND l.valueuom = 'mg/dL';