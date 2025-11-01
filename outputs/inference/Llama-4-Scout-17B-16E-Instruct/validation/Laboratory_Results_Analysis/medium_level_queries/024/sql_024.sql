WITH 
-- Calculate 99th percentile of hs-Troponin T
troponin_percentile AS (
  SELECT 
    APPROX_QUANTILES(valuenum, 100)[99] AS troponin_99th_percentile
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    itemid = 220052  -- hs-Troponin T
),

-- Identify target patients
target_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admission_type,
    a.hospital_expire_flag,
    le.valuenum AS troponin_value
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    (SELECT 
       subject_id, 
       hadm_id, 
       valuenum,
       ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime) AS rn
     FROM 
       `physionet-data.mimiciv_3_1_hosp.labevents`
     WHERE 
       itemid = 220052  -- hs-Troponin T
    ) le 
      ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
  WHERE 
    p.gender = 'M' AND
    p.anchor_age BETWEEN 64 AND 74 AND
    a.admission_type LIKE '%Chest Pain%' AND
    le.rn = 1
),

-- Apply troponin threshold
high_troponin_patients AS (
  SELECT 
    subject_id,
    hadm_id,
    anchor_age,
    gender,
    admission_type,
    hospital_expire_flag,
    troponin_value
  FROM 
    target_patients
  CROSS JOIN 
    troponin_percentile
  WHERE 
    troponin_value > troponin_99th_percentile
)

-- Calculate summary statistics and mortality rate
SELECT 
  COUNT(*) AS patient_count,
  AVG(troponin_value) AS mean_troponin,
  APPROX_QUANTILES(troponin_value, 100)[50] AS median_troponin,
  SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality_rate
FROM 
  high_troponin_patients;