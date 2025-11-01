WITH eligible_patients AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 75 AND 85
),
relevant_procedures AS (
  SELECT 
    ep.subject_id,
    ep.hadm_id,
    pi.icd_code
  FROM 
    eligible_patients ep
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON ep.hadm_id = pi.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code
    AND pi.icd_version = dip.icd_version
  WHERE 
    pi.icd_version = 9  -- Primarily ICD-9 in MIMIC-IV procedures
    AND (
      pi.icd_code = '37.34'  -- Catheter ablation of heart tissue
      OR pi.icd_code = '37.94'  -- Cardioversion
    )
),
patient_procedure_counts AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT CONCAT(hadm_id, '|', icd_code)) AS distinct_procedures
  FROM 
    relevant_procedures
  GROUP BY 
    subject_id
)
SELECT 
  (SELECT PERCENTILE_CONT(distinct_procedures, 0.25) FROM patient_procedure_counts) AS q1,
  (SELECT PERCENTILE_CONT(distinct_procedures, 0.75) FROM patient_procedure_counts) AS q3,
  (SELECT PERCENTILE_CONT(distinct_procedures, 0.75) FROM patient_procedure_counts) - 
  (SELECT PERCENTILE_CONT(distinct_procedures, 0.25) FROM patient_procedure_counts) AS iqr
FROM patient_procedure_counts
LIMIT 1;