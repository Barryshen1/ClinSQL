WITH 
-- Identify serum glucose itemids
glucose_itemids AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
  WHERE label LIKE '%Glucose%'
),

-- Identify pneumonia patients who are 67 years old and male
pneumonia_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M' 
    AND p.anchor_age = 67 
    AND d.icd_code LIKE 'Pneumonia%'  
),

-- Extract serum glucose measurements within the first 24 hours
glucose_measurements AS (
  SELECT 
    l.subject_id, 
    l.hadm_id, 
    l.valuenum, 
    l.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN glucose_itemids g 
    ON l.itemid = g.itemid
  JOIN pneumonia_patients p 
    ON l.hadm_id = p.hadm_id
  WHERE l.charttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 24 HOUR)
)

-- Calculate mean serum glucose for each patient and find 75th percentile
SELECT 
  APPROX_QUANTILES(mean_glucose, 100)[OFFSET(75)] AS percentile_75
FROM (
  SELECT 
    subject_id, 
    AVG(valuenum) AS mean_glucose
  FROM glucose_measurements
  GROUP BY subject_id
);