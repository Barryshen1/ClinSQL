WITH 
-- Identify mechanical circulatory support procedures
mechanical_circulatory_support_procedures AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE long_title LIKE '%mechanical circulatory support%'
),

-- Filter patients and admissions
patients_admissions AS (
  SELECT a.hadm_id, p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 80 AND 90 
  AND p.gender = 'M'
),

-- Identify procedures for patients
patient_procedures AS (
  SELECT pa.subject_id, pi.icd_code
  FROM patients_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
  ON pa.hadm_id = pi.hadm_id
  JOIN mechanical_circulatory_support_procedures mcs 
  ON pi.icd_code = mcs.icd_code
)

-- Find the maximum count of distinct procedures
SELECT 
  MAX(distinct_procedures) AS max_distinct_procedures
FROM (
  SELECT 
    subject_id, 
    COUNT(DISTINCT icd_code) AS distinct_procedures
  FROM patient_procedures
  GROUP BY subject_id
);