WITH patient_procedures AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT CASE 
      WHEN (pi.icd_version = 9 AND pi.icd_code BETWEEN '37.31' AND '37.39') 
      OR (pi.icd_version = 10 AND pi.icd_code BETWEEN '05H0' AND '05H9') THEN pi.icd_code 
      END) AS mcs_procedures
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON p.subject_id = pi.subject_id
  WHERE 
    p.gender = 'F' AND p.anchor_age BETWEEN 43 AND 53
  GROUP BY 
    p.subject_id
)
SELECT 
  PERCENTILE_CONT(0.25)(mcs_procedures) AS percentile_25
FROM 
  patient_procedures;