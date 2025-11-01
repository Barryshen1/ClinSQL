WITH cohort_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
),
valve_procedures AS (
  SELECT DISTINCT cp.subject_id, pi.icd_code
  FROM cohort_patients cp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON cp.subject_id = pi.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip ON pi.icd_code = dip.icd_code 
    AND CAST(pi.icd_version AS STRING) = dip.icd_version
  WHERE pi.icd_version = 10  -- Focus on ICD-10 for modern procedures
    AND REGEXP_CONTAINS(pi.icd_code, r'^0(25|2C|2R).*')  -- Valve repair/replacement codes (e.g., 025*, 02C*, 02R*)
    AND (dip.long_title LIKE '%valve%' OR dip.long_title LIKE '%prosthetic%')
)
SELECT 
  AVG(procedure_count) AS avg_distinct_valve_procedures_per_patient
FROM (
  SELECT subject_id, COUNT(DISTINCT icd_code) AS procedure_count
  FROM valve_procedures
  GROUP BY subject_id
) patient_procs;