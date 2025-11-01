WITH 
-- Identify serum creatinine itemid
serum_creatinine_item AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
  WHERE label LIKE '%Creatinine%'
),

-- Extract relevant patient admissions and lab events
patient_data AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime,
    le.charttime,
    le.valuenum AS creatinine_value
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON a.hadm_id = le.hadm_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age = 56 
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.hadm_id = a.hadm_id 
      AND di.icd_code LIKE '%COPD%'
    )
    AND le.itemid IN (SELECT itemid FROM serum_creatinine_item)
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
),

-- Calculate average creatinine for each patient
patient_avg_creatinine AS (
  SELECT 
    subject_id, 
    AVG(creatinine_value) AS avg_creatinine
  FROM 
    patient_data
  GROUP BY 
    subject_id
)

-- Calculate 75th percentile of average creatinine
SELECT 
  APPROX_QUANTILES(avg_creatinine, 4)[OFFSET(3)] AS percentile_75
FROM 
  patient_avg_creatinine;