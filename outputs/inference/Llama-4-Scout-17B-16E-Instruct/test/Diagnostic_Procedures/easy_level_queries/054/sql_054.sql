WITH 
  -- Get patient admissions, procedures and echo procedures
  patient_procedures AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      COUNT(DISTINCT pr.icd_code) AS num_procedures
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` pt 
        ON a.subject_id = pt.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr 
        ON a.hadm_id = pr.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp 
        ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
    WHERE 
      pt.gender = 'F' 
      AND pt.anchor_age BETWEEN 81 AND 91
      AND (dp.long_title LIKE '%echocardiography%' OR dp.long_title LIKE '%echo%')
    GROUP BY 
      a.subject_id, 
      a.hadm_id
  )

-- Find the maximum number of distinct echocardiography procedures per patient
SELECT 
  MAX(num_procedures) AS max_num_procedures
FROM 
  patient_procedures;