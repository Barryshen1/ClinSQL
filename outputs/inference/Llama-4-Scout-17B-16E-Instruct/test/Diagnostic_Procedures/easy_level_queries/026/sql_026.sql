WITH patient_procedures AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    icd.icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` icd
  ON 
    p.subject_id = icd.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
),
catheter_ablation_cardioversion AS (
  SELECT 
    subject_id,
    icd_code
  FROM 
    patient_procedures
  WHERE 
    icd_code IN (
      SELECT 
        dip.icd_code 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
      WHERE 
        dip.long_title LIKE '%Catheter ablation%' 
        OR dip.long_title LIKE '%Cardioversion%'
    )
),
num_procedures AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT icd_code) AS num_procedures
  FROM 
    catheter_ablation_cardioversion
  GROUP BY 
    subject_id
)
SELECT 
  APPROX_QUANTILES(num_procedures, 25) AS Q1,
  APPROX_QUANTILES(num_procedures, 50) AS median,
  APPROX_QUANTILES(num_procedures, 75) AS Q3,
  APPROX_QUANTILES(num_procedures, 75) - APPROX_QUANTILES(num_procedures, 25) AS IQR
FROM 
  num_procedures;