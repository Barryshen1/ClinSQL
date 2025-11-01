WITH patient_procedure_counts AS (
  SELECT 
    p.subject_id,
    COUNT(pi.icd_code) AS procedure_count
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  LEFT JOIN 
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi
    ON p.subject_id = pi.subject_id
  LEFT JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
    AND (
      LOWER(dip.long_title) LIKE '%catheter ablation%' 
      OR LOWER(dip.long_title) LIKE '%cardioversion%'
    )
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 86 AND 96
  GROUP BY 
    p.subject_id
)
SELECT 
  STDDEV(procedure_count) AS sd_procedures_per_patient
FROM 
  patient_procedure_counts;