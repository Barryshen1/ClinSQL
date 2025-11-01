WITH 
  -- Define pacemaker/ICD procedures
  pacemaker_icd_codes AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE 
      (icd_version = 9 AND icd_code IN ('37.81', '37.82', '37.83', '37.84', '37.85', '37.86', '37.87', '37.88', '37.89', '37.9'))
      OR 
      (icd_version = 10 AND icd_code IN ('0.1', '0.2', '0.3', '0.4', '0.5', '0.6', '0.7', '0.8', '0.9'))
  ),
  
  -- Select patients and procedures
  patient_procedures AS (
    SELECT 
      p.subject_id,
      COUNT(DISTINCT pi.icd_code) AS procedure_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON 
      p.subject_id = pi.subject_id
    AND 
      pi.icd_code IN (SELECT icd_code FROM pacemaker_icd_codes)
    WHERE 
      p.gender = 'M'
    AND 
      p.anchor_age BETWEEN 78 AND 88
    GROUP BY 
      p.subject_id
  )

-- Calculate 25th percentile
SELECT 
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(1)] AS percentile_25
FROM 
  patient_procedures;