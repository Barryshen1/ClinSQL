WITH patient_demographics AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 57 AND 67
),
echocardiography_procedures AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT pi.icd_code) AS distinct_ecg_procedures
  FROM 
    patient_demographics p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
      ON p.subject_id = pi.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
      ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE 
    dip.long_title LIKE '%Echocardiography%'
  GROUP BY 
    p.subject_id
)
SELECT 
  APPROX_QUANTILES(distinct_ecg_procedures, 100)[75] AS percentile_75
FROM 
  echocardiography_procedures;