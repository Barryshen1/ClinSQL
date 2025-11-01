SELECT
  APPROX_QUANTILES(valuenum, 1000)[OFFSET(750)] - APPROX_QUANTILES(valuenum, 1000)[OFFSET(250)] AS iqr_glucose
FROM (
  SELECT le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab
    ON le.itemid = d_lab.itemid
  WHERE p.gender = 'M'
    AND d_diag.icd_code LIKE 'I63%'
    AND LOWER(d_lab.label) = 'glucose'
    AND d_lab.fluid = 'Blood'
    AND DATE(le.charttime) = DATE(a.dischtime)
    AND le.valuenum IS NOT NULL
) sub;