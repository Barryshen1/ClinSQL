WITH 
  -- Filter patients to only include females aged 64-74
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' 
      AND anchor_age BETWEEN 64 AND 74
  ),
  
  -- Identify diagnostic cardiac catheterization procedures
  cath_procedures AS (
    SELECT subject_id, COUNT(DISTINCT hadm_id) AS procedure_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE icd_code IN (
      '88.57', '88.58',  -- ICD-9
      '0.24', '0.25', '0.26', '0.27', '0.28', '0.29', 
      '0.2A', '0.2B', '0.2D', '0.2E', '0.2F', '0.2G', 
      '0.2H', '0.2J', '0.2K', '0.2L', '0.2M', '0.2N', 
      '0.2P', '0.2Q', '0.2R', '0.2S', '0.2T', '0.2U', 
      '0.2V', '0.2W', '0.2X', '0.2Y', '0.2Z'  -- ICD-10
    )
    GROUP BY subject_id
  )

-- Find the minimum count of procedures per patient
SELECT 
  MIN(procedure_count) AS min_procedures_per_patient
FROM 
  cath_procedures
  INNER JOIN target_patients tp 
    ON cath_procedures.subject_id = tp.subject_id;