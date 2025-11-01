WITH 
  -- Filter patients by age and gender
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 52 AND 62
  ),
  
  -- Link patients to their hospital admissions and procedures
  patient_procedures AS (
    SELECT 
      a.hadm_id,
      p.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN target_patients tp ON a.subject_id = tp.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON a.hadm_id = p.hadm_id
    WHERE p.icd_code IN (
      -- Valve repair/replacement ICD codes (example codes, might need adjustment)
      '35.0', '35.1', '35.2', '35.3', '35.4', '35.5', '35.6', '35.7', '35.8', '35.9',
      '36.0', '36.1', '36.2', '36.3', '36.4', '36.5', '36.6', '36.7', '36.8', '36.9'
    )
  ),
  
  -- Count distinct procedures per hospitalization
  procedure_counts AS (
    SELECT 
      hadm_id,
      COUNT(DISTINCT icd_code) AS distinct_procedures
    FROM patient_procedures
    GROUP BY hadm_id
  )

-- Calculate the interquartile range (IQR)
SELECT 
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY distinct_procedures) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY distinct_procedures) AS iqr
FROM procedure_counts;