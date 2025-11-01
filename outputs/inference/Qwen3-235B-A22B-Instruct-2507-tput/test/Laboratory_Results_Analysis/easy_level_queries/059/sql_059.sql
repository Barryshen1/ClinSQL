SELECT
  APPROX_QUANTILES(le.valuenum, 1000)[OFFSET(750)] AS platelet_count_75th_percentile
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON a.hadm_id = di.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
  ON di.icd_code = d_diag.icd_code AND di.icd_version = d_diag.icd_version
JOIN
  `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON a.hadm_id = le.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab
  ON le.itemid = d_lab.itemid
WHERE
  p.gender = 'M'
  AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) = 93
  AND d_diag.icd_version = 10
  AND d_diag.icd_code IN ('A419', 'R6520', 'R6521')
  AND LOWER(d_lab.label) = 'platelets'
  AND le.valuenum IS NOT NULL
  AND DATE(le.charttime) = DATE(a.dischtime);