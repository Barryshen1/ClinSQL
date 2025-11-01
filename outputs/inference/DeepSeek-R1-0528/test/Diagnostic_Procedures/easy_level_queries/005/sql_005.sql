WITH echo_procedures AS (
  -- ICD procedures (procedures_icd)
  SELECT 
    proc.subject_id, 
    proc.chartdate AS procedure_date
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` diag 
    ON proc.icd_code = diag.icd_code 
    AND proc.icd_version = diag.icd_version
  WHERE 
    LOWER(diag.long_title) LIKE '%echocardiogram%' OR
    LOWER(diag.long_title) LIKE '%echocardiography%' OR
    (LOWER(diag.long_title) LIKE '% echo %' AND LOWER(diag.long_title) NOT LIKE '%echoencephalogram%') OR
    (LOWER(diag.long_title) LIKE 'echo %' AND LOWER(diag.long_title) NOT LIKE 'echoencephalogram%') OR
    (LOWER(diag.long_title) LIKE '% echo' AND LOWER(diag.long_title) NOT LIKE '%echoencephalogram')

  UNION ALL

  -- HCPCS procedures (hcpcsevents)
  SELECT 
    hcpc.subject_id, 
    hcpc.chartdate AS procedure_date
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh 
    ON hcpc.hcpcs_cd = dh.code
  WHERE 
    LOWER(dh.long_description) LIKE '%echocardiogram%' OR
    LOWER(dh.long_description) LIKE '%echocardiography%' OR
    (LOWER(dh.long_description) LIKE '% echo %' AND LOWER(dh.long_description) NOT LIKE '%echoencephalogram%') OR
    (LOWER(dh.long_description) LIKE 'echo %' AND LOWER(dh.long_description) NOT LIKE 'echoencephalogram%') OR
    (LOWER(dh.long_description) LIKE '% echo' AND LOWER(dh.long_description) NOT LIKE '%echoencephalogram')
),

patient_echo_counts AS (
  SELECT 
    p.subject_id,
    COUNT(e.procedure_date) AS echo_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  LEFT JOIN echo_procedures e 
    ON p.subject_id = e.subject_id
    AND DATE_DIFF(
        e.procedure_date, 
        DATE(p.anchor_year - p.anchor_age, 1, 1), 
        YEAR
    ) BETWEEN 57 AND 67  -- Exact age at procedure time
  WHERE 
    p.gender = 'M'  -- Male patients
  GROUP BY p.subject_id
)

SELECT 
  APPROX_QUANTILES(echo_count, 100)[OFFSET(75)] AS percentile_75
FROM patient_echo_counts;