WITH sepsis_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M' AND icd.long_title LIKE '%Sepsis%'
),
lactate_measurements AS (
  SELECT l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON l.itemid = di.itemid
  INNER JOIN sepsis_admissions a ON l.hadm_id = a.hadm_id
  WHERE di.label LIKE '%Lactate%' AND TIMESTAMP_TRUNC(l.charttime, DAY) = TIMESTAMP_TRUNC(a.dischtime, DAY)
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr
FROM lactate_measurements;