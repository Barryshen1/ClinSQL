WITH filtered_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 75 AND 85
),
procedures AS (
  SELECT 
    hadm_id,
    COUNT(*) AS proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE 
    -- Catheter ablation (ICD-9 and ICD-10)
    (icd_version = 9 AND icd_code = '37.34')
    OR (icd_version = 10 AND icd_code LIKE '025%' AND SUBSTR(icd_code, 5, 1) IN ('3', '4'))
    -- Cardioversion (ICD-9 and ICD-10)
    OR (icd_version = 9 AND icd_code = '99.51')
    OR (icd_version = 10 AND icd_code IN ('5A2204Z', '5A2234Z'))
  GROUP BY hadm_id
),
patient_procedure_counts AS (
  SELECT 
    fa.subject_id,
    COALESCE(p.proc_count, 0) AS total_procs
  FROM filtered_admissions fa
  LEFT JOIN procedures p
    ON fa.hadm_id = p.hadm_id
),
aggregated_counts AS (
  SELECT 
    subject_id,
    SUM(total_procs) AS total_procs_per_patient
  FROM patient_procedure_counts
  GROUP BY subject_id
)
SELECT 
  APPROX_QUANTILES(total_procs_per_patient, 1000)[OFFSET(750)] 
  - APPROX_QUANTILES(total_procs_per_patient, 1000)[OFFSET(250)] AS iqr
FROM aggregated_counts;