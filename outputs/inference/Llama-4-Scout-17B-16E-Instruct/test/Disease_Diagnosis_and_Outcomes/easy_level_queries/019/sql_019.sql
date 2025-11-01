WITH 
  -- Identify patients with primary sepsis/septic shock
  sepsis_patients AS (
    SELECT 
      di.subject_id,
      di.hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE 
      di.icd_code IN ('038', '995.0', '995.1', '995.2', 'A41', 'R65.2')
      AND di.seq_num = 1  -- Primary diagnosis
  ),
  
  -- Filter patients by age and gender
  filtered_patients AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      a.hadm_id,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    WHERE 
      p.anchor_age BETWEEN 67 AND 77
      AND p.gender = 'F'
  )

-- Calculate SD of hospital length of stay
SELECT 
  STDDEV(fp.los_days) AS sd_los_days
FROM 
  filtered_patients fp
WHERE 
  fp.hadm_id IN (SELECT hadm_id FROM sepsis_patients);