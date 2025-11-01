WITH mcs_procedures AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS mcs_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  ON 
    a.hadm_id = proc.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
  ON 
    proc.icd_code = d_proc.icd_code 
    AND proc.icd_version = CAST(d_proc.icd_version AS INT64)
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.hospital_expire_flag = 0
    AND (
      -- ICD-9 codes for MCS
      (proc.icd_version = 9 AND proc.icd_code IN ('3761', '3762', '3965')) OR
      -- ICD-10 codes for MCS (root codes)
      (proc.icd_version = 10 AND (
        proc.icd_code LIKE '02RK%' OR  -- IABP
        proc.icd_code LIKE '02WA%' OR  -- VAD
        proc.icd_code = '5A0221Z'      -- ECMO
      ))
    )
  GROUP BY 
    p.subject_id, p.hadm_id
)

SELECT 
  PERCENTILE_CONT(0.25, 0) OVER (ORDER BY mcs_count) AS iqr_lower,
  PERCENTILE_CONT(0.75, 0) OVER (ORDER BY mcs_count) AS iqr_upper
FROM 
  mcs_procedures;