WITH 
  -- Identify relevant patients
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 86 AND 96
  ),
  
  -- Identify catheter ablation and cardioversion procedures
  target_procedures AS (
    SELECT icd_code, icd_version, long_title
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE long_title IN ('Catheter ablation', 'Cardioversion')
  ),
  
  -- Link patients with their procedures
  patient_procedures AS (
    SELECT p.subject_id, COUNT(DISTINCT pi.icd_code) as procedure_count
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON p.subject_id = pi.subject_id
    JOIN target_procedures tp ON pi.icd_code = tp.icd_code AND pi.icd_version = tp.icd_version
    WHERE p.subject_id IN (SELECT subject_id FROM target_patients)
    GROUP BY p.subject_id
  )

-- Calculate the standard deviation of distinct procedures per patient
SELECT 
  STDDEV(procedure_count) as sd_procedures
FROM patient_procedures;