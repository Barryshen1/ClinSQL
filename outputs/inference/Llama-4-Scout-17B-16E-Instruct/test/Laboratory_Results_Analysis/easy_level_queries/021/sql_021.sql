WITH 
-- Identify male patients with pneumonia admissions
male_pneumonia_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
  AND dd.long_title LIKE '%Pneumonia%'
),

-- Identify serum glucose lab events at discharge
discharge_glucose AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS glucose_level
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE 
    dl.label = 'Glucose'
  AND l.charttime = (SELECT MAX(charttime) FROM `physionet-data.mimiciv_3_1_hosp.labevents` le WHERE le.hadm_id = l.hadm_id)
  AND l.hadm_id IN (SELECT hadm_id FROM male_pneumonia_admissions)
)

-- Calculate 75th percentile of serum glucose
SELECT 
  APPROX_QUANTILES(glucose_level, 4)[OFFSET(3)] AS percentile_75_glucose
FROM 
  discharge_glucose;