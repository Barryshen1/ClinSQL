WITH 
-- Identify serum creatinine itemid
serum_creatinine_item AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
  WHERE label LIKE '%Serum Creatinine%'
),

-- Identify patients with COPD
copd_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` i ON d.icd_code = i.icd_code AND d.icd_version = i.icd_version
  WHERE i.long_title LIKE '%COPD%' 
  AND a.admit_provider_id IS NOT NULL  -- Ensure proper admission records
),

-- Filter patients and get serum creatinine measurements
patient_data AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    a.hadm_id, 
    a.admittime,
    le.valuenum,
    le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON a.hadm_id = le.hadm_id
  JOIN serum_creatinine_item sci ON le.itemid = sci.itemid
  WHERE p.anchor_age = 90 
  AND p.gender = 'M'
  AND a.hadm_id IN (SELECT hadm_id FROM copd_patients)
  AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
)

-- Calculate standard deviation of serum creatinine
SELECT 
  STDDEV(valuenum) AS std_dev_serum_creatinine
FROM patient_data;