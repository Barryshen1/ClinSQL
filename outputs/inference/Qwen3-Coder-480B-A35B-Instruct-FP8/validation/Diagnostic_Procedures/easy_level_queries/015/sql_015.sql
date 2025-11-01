WITH cabg_patients AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT proc.icd_code, proc.icd_version) AS distinct_cabg_count
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  LEFT JOIN 
    physionet-data.mimiciv_3_1_hosp.procedures_icd proc
    ON p.subject_id = proc.subject_id
  LEFT JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures d_proc
    ON proc.icd_code = d_proc.icd_code 
    AND proc.icd_version = d_proc.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND LOWER(d_proc.long_title) LIKE '%coronary%'
    AND LOWER(d_proc.long_title) LIKE '%bypass%'
  GROUP BY 
    p.subject_id
)

SELECT 
  APPROX_QUANTILES(distinct_cabg_count, 100)[OFFSET(25)] AS percentile_25_distinct_cabg
FROM 
  cabg_patients;