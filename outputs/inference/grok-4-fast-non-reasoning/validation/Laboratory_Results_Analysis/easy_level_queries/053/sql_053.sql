WITH stroke_patients AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age = 82
    AND d.seq_num = 1
    AND d.icd_code LIKE 'I63%'
    AND d.icd_version = 10  -- Focus on ICD-10 for modern ischemic stroke codes
),
admission_glucose AS (
  SELECT 
    sp.subject_id,
    sp.hadm_id,
    MIN(le.valuenum) AS min_glucose
  FROM 
    stroke_patients sp
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sp.hadm_id = le.hadm_id
  WHERE 
    le.itemid IN (225624, 225655)  -- Serum glucose itemids
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'mg/dL'
    AND DATE(le.charttime) = DATE(sp.admittime)  -- Within admission day
  GROUP BY 
    sp.subject_id, sp.hadm_id
  HAVING 
    min_glucose IS NOT NULL  -- Ensure valid glucose values
)
SELECT 
  PERCENTILE_CONT(min_glucose, 0.75) AS p75_admission_glucose_mg_dl
FROM 
  admission_glucose;