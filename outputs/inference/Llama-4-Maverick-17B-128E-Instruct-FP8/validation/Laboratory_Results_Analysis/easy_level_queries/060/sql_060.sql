WITH pneumonia_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age = 67
  AND d.icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE lower(long_title) LIKE '%pneumonia%')
  AND d.icd_version = 10
),
glucose_measurements AS (
  SELECT a.hadm_id, l.valuenum
  FROM pneumonia_admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.label LIKE '%Glucose%' AND DATETIME_DIFF(l.charttime, a.admittime, HOUR) <= 24
),
mean_glucose AS (
  SELECT hadm_id, AVG(valuenum) AS mean_glucose
  FROM glucose_measurements
  GROUP BY hadm_id
)
SELECT APPROX_QUANTILES(mean_glucose, 100)[OFFSET(75)] AS percentile_75th
FROM mean_glucose;