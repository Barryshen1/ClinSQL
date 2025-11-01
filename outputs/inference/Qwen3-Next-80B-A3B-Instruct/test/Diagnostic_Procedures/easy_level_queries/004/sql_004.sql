WITH cabg_counts_per_patient AS (
  SELECT 
    p.subject_id,
    COUNT(*) AS cabg_procedure_count
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi
    ON p.subject_id = pi.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 41 AND 51
    AND LOWER(dip.long_title) LIKE '%cabg%'
  GROUP BY 
    p.subject_id
)
SELECT 
  STDDEV_POP(cabg_procedure_count) AS std_dev_cabg_per_patient
FROM 
  cabg_counts_per_patient;