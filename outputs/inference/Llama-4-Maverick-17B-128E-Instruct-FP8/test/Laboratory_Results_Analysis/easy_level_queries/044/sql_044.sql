WITH ischemic_stroke_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' AND dicd.long_title LIKE '%Ischemic stroke%'
),
glucose_measurements AS (
  SELECT l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  INNER JOIN ischemic_stroke_admissions isa ON l.hadm_id = isa.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
  WHERE dl.label LIKE '%Glucose%' AND l.valuenum IS NOT NULL
  AND DATE(l.charttime) = DATE(a.dischtime)
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS Q1,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS Q3
FROM glucose_measurements;