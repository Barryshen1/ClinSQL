WITH cardiac_catheterization_procedures AS (
  SELECT 
    p.subject_id,
    COUNT(*) AS procedure_count
  FROM 
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON pi.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND LOWER(dip.long_title) LIKE '%cardiac catheterization%'
  GROUP BY 
    p.subject_id
)
SELECT 
  MIN(procedure_count) AS min_procedures_per_patient
FROM 
  cardiac_catheterization_procedures;