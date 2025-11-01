WITH 
  -- Identify patients with acute pancreatitis (ICD-9: 577.0, ICD-10: K85)
  pancreatitis_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      p.anchor_age, 
      p.gender,
      a.admittime,
      a.dischtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE 
          d.hadm_id = a.hadm_id
          AND d.icd_code IN ('577.0', 'K85')
      )
      AND p.gender = 'M'
      AND p.anchor_age BETWEEN 42 AND 52
  ),
  
  -- Calculate LOS and categorize it
  patient_los AS (
    SELECT 
      subject_id, 
      hadm_id, 
      TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
    FROM 
      pancreatitis_patients
  ),
  
  -- Count diagnostic procedures per admission
  procedures_per_admission AS (
    SELECT 
      hadm_id, 
      COUNT(*) AS procedure_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY 
      hadm_id
  )

-- Final query
SELECT 
  CASE 
    WHEN los BETWEEN 1 AND 4 THEN '1-4'
    WHEN los BETWEEN 5 AND 7 THEN '5-7'
  END AS los_category,
  COUNT(DISTINCT p.hadm_id) AS patient_count,
  AVG(pp.procedure_count) AS mean_procedures,
  MIN(pp.procedure_count) AS min_procedures,
  MAX(pp.procedure_count) AS max_procedures
FROM 
  patient_los p
JOIN 
  procedures_per_admission pp 
    ON p.hadm_id = pp.hadm_id
GROUP BY 
  CASE 
    WHEN los BETWEEN 1 AND 4 THEN '1-4'
    WHEN los BETWEEN 5 AND 7 THEN '5-7'
  END
ORDER BY 
  los_category;