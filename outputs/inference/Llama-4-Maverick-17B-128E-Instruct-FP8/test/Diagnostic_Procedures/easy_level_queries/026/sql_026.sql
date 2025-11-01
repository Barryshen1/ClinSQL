WITH relevant_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE icd_version = 10 AND (long_title LIKE '%catheter ablation%' OR long_title LIKE '%cardioversion%')
),
relevant_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 75 AND 85
),
relevant_procedures AS (
  SELECT subject_id, icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE icd_version = 10 AND icd_code IN (SELECT icd_code FROM relevant_icd_codes)
),
patient_procedures AS (
  SELECT rp.subject_id, COUNT(DISTINCT rp.icd_code) as num_procedures
  FROM relevant_procedures rp
  JOIN relevant_patients p ON rp.subject_id = p.subject_id
  GROUP BY rp.subject_id
)
SELECT 
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS Q1,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS Q3,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] - APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS IQR
FROM patient_procedures;