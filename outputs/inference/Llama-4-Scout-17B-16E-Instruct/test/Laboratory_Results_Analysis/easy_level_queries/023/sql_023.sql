WITH 
-- Identify lactate itemid
lactate_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
  WHERE label LIKE '%Lactate%'
),

-- Identify male patients with sepsis
sepsis_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
  AND (d.icd_code IN ('995.91', '998.0') OR d.icd_code LIKE 'A41.%' OR d.icd_code IN ('R65.20', 'R65.21'))
),

-- Identify lactate measurements on discharge day
lactate_discharge AS (
  SELECT s.hadm_id, s.dischtime, l.valuenum
  FROM sepsis_patients s
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON s.hadm_id = l.hadm_id
  JOIN lactate_itemid li ON l.itemid = li.itemid
  WHERE l.charttime BETWEEN TIMESTAMP_SUB(s.dischtime, INTERVAL 1 DAY) AND s.dischtime
)

-- Calculate IQR of lactate on discharge day
SELECT 
  APPROX_QUANTILES(valuenum, 25) AS Q1,
  APPROX_QUANTILES(valuenum, 50) AS Median,
  APPROX_QUANTILES(valuenum, 75) AS Q3,
  APPROX_QUANTILES(valuenum, 75) - APPROX_QUANTILES(valuenum, 25) AS IQR
FROM lactate_discharge;