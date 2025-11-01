SELECT
  PERCENTILE_CONT(valuenum, 0.75) OVER() - PERCENTILE_CONT(valuenum, 0.25) OVER() AS iqr_lactate
FROM (
  SELECT DISTINCT le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
    ON di.icd_code = d_diag.icd_code AND di.icd_version = d_diag.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
    ON a.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems d_lab
    ON le.itemid = d_lab.itemid
  WHERE p.gender = 'M'
    AND d_diag.icd_code LIKE 'A41%'
    AND d_lab.label = 'Lactate'
    AND DATE(le.charttime) = DATE(a.dischtime)
    AND le.valuenum IS NOT NULL
);