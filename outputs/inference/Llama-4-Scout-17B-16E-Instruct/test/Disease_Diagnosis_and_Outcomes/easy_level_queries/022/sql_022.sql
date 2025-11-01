WITH 
  -- Filter patients and admissions
  eligible_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 71 AND 81
  ),
  
  -- Identify primary ischemic stroke admissions
  ischemic_stroke_admissions AS (
    SELECT 
      ea.subject_id,
      ea.hadm_id,
      ea.admittime,
      ea.dischtime
    FROM 
      eligible_patients ea
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      ON ea.hadm_id = di.hadm_id
    WHERE 
      di.icd_code LIKE 'I63%'
      AND di.seq_num = 1
  ),
  
  los_data AS (
    SELECT 
      TIMESTAMPDIFF(DAY, admittime, dischtime) AS los
    FROM 
      ischemic_stroke_admissions
  )

SELECT 
  APPROX_QUANTILES(los, 100)[25] AS q1,
  APPROX_QUANTILES(los, 100)[75] AS q3,
  APPROX_QUANTILES(los, 100)[75] - APPROX_QUANTILES(los, 100)[25] AS iqr
FROM 
  los_data;