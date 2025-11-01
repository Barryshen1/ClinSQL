WITH 
  -- Get distinct procedure codes per patient
  patient_procedures AS (
    SELECT 
      p.subject_id, 
      COUNT(DISTINCT pi.icd_code) AS num_procedures
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON a.hadm_id = pi.hadm_id
    WHERE 
      p.anchor_age BETWEEN 81 AND 91
      AND p.gender = 'M'
      AND pi.icd_code LIKE '4%'  -- ECG/telemetry procedure codes are in the 4xxxx range
    GROUP BY 
      p.subject_id
  )

-- Calculate the standard deviation
SELECT 
  STDDEV(num_procedures) AS std_dev
FROM 
  patient_procedures;