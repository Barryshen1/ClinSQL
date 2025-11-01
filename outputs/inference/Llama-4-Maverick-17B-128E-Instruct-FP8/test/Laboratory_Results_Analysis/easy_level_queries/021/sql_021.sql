WITH pneumonia_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND dicd.long_title LIKE '%Pneumonia%'
),
glucose_measurements AS (
  SELECT l.hadm_id, l.valuenum, a.dischtime, l.charttime,
         TIMESTAMP_DIFF(l.charttime, a.dischtime, HOUR) AS hours_diff
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
  WHERE dl.label LIKE '%Glucose%' AND dl.fluid = 'Blood'
),
glucose_at_discharge AS (
  SELECT hadm_id, valuenum
  FROM glucose_measurements
  WHERE ABS(hours_diff) <= 24  
)
SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS glucose_75th_percentile
FROM glucose_at_discharge
WHERE hadm_id IN (SELECT hadm_id FROM pneumonia_admissions);