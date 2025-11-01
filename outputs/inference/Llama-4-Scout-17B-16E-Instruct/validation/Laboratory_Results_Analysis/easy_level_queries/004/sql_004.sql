WITH 
-- Identify sepsis patients
sepsis_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    (d.icd_code LIKE '995.91'  -- Sepsis ICD-9 code
    OR d.icd_code LIKE 'S sepsis')  -- Sepsis ICD-10 code
    AND p.gender = 'F'
    AND p.anchor_age = 76
),

-- Get platelet counts for sepsis patients
platelet_counts AS (
  SELECT 
    sp.hadm_id,
    le.charttime,
    le.valuenum AS platelet_count
  FROM 
    sepsis_patients sp
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON sp.hadm_id = le.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl 
      ON le.itemid = dl.itemid
  WHERE 
    dl.label = 'Platelet Count'
    AND le.charttime BETWEEN sp.admittime AND TIMESTAMP_ADD(sp.admittime, INTERVAL 1 DAY)
    AND le.valuenum IS NOT NULL
)

-- Calculate median platelet count
SELECT 
  APPROX_QUANTILES(platelet_count, 100)[OFFSET(50)] AS median_platelet_count
FROM 
  platelet_counts;