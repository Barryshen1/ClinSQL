WITH troponin_i AS (
  SELECT l.hadm_id, l.valuenum, ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.itemid = 50821  
),
admissions_with_troponin AS (
  SELECT a.hadm_id, a.admittime, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 90 AND 100
  AND a.hadm_id IN (SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` WHERE icd_code IN ('I20.0', 'I20.1', 'I20.8', 'I20.9', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9', 'R07.2'))  
),
first_troponin AS (
  SELECT awt.hadm_id, ti.valuenum
  FROM admissions_with_troponin awt
  INNER JOIN troponin_i ti ON awt.hadm_id = ti.hadm_id
  WHERE ti.rn = 1 AND ti.valuenum IS NOT NULL
)
SELECT 
  PERCENTILE_CONT(valuenum, 0.25) AS p25,
  PERCENTILE_CONT(valuenum, 0.5) AS p50,
  PERCENTILE_CONT(valuenum, 0.75) AS p75,
  MAX(valuenum) - MIN(valuenum) AS `range`
FROM first_troponin;