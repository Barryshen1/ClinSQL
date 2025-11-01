WITH echo_procedures AS (
  SELECT 
    p.subject_id,
    pi.hadm_id,
    pi.icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    pi.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
  ON 
    pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND (LOWER(dip.long_title) LIKE '%echocardiography%' 
         OR pi.icd_code IN ('37.28', '89.0'))  -- Specific ICD codes for echo
),
counts_per_hadm AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_echo_procedures
  FROM 
    echo_procedures
  GROUP BY 
    hadm_id
)
SELECT 
  PERCENTILE_CONT(0.25, num_echo_procedures) OVER() AS p25_num_echo_procedures
FROM 
  counts_per_hadm;