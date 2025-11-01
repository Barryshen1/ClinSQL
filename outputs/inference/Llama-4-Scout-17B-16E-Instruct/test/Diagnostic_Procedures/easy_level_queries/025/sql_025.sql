WITH 
  -- Identify mechanical circulatory support procedures
  mcs_procedures AS (
    SELECT 
      icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE 
      long_title LIKE '%mechanical circulatory support%' 
      OR long_title LIKE '%ventricular assist device%' 
      OR long_title LIKE '%extracorporeal membrane oxygenation%'
  ),
  
  -- Patient procedures
  patient_procedures AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      pi.icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
        ON p.subject_id = pi.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 40 AND 50
      AND pi.icd_code IN (SELECT icd_code FROM mcs_procedures)
  )

-- Calculate distinct procedures per patient
SELECT 
  subject_id,
  COUNT(DISTINCT icd_code) AS num_distinct_mcs_procedures
FROM 
  patient_procedures
GROUP BY 
  subject_id
ORDER BY 
  num_distinct_mcs_procedures ASC
LIMIT 1;