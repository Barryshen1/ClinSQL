WITH 
-- Define platelet count itemid
platelet_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
  WHERE label LIKE '%Platelet%'
),

-- Identify sepsis admissions
sepsis_admissions AS (
  SELECT hadm_id 
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
  WHERE icd_code IN ('995.91', '995.92', 'A40', 'A41')
),

-- Get admission platelet counts for male sepsis patients
platelet_counts AS (
  SELECT 
    a.hadm_id,
    le.valuenum AS platelet_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON a.hadm_id = le.hadm_id
  JOIN 
    platelet_itemid pi 
      ON le.itemid = pi.itemid
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age = 44
    AND a.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
    AND le.charttime BETWEEN a.admittime AND a.dischtime
)

-- Calculate standard deviation of admission platelet counts
SELECT 
  STDDEV(platelet_count) AS std_dev_platelet_count
FROM 
  platelet_counts;