WITH procedure_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    LOWER(long_title) LIKE '%catheter ablation%' OR 
    LOWER(long_title) LIKE '%cardioversion%'
),
cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
cohort_filtered AS (
  SELECT subject_id, hadm_id
  FROM cohort
  WHERE age_at_admission BETWEEN 75 AND 85
),
distinct_procedures AS (
  SELECT 
    cf.subject_id,
    proc.icd_code
  FROM cohort_filtered cf
  LEFT JOIN (
    SELECT 
      p.hadm_id, 
      p.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN procedure_codes pc 
      ON p.icd_code = pc.icd_code 
      AND p.icd_version = pc.icd_version
  ) proc
    ON cf.hadm_id = proc.hadm_id
),
procedure_counts AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT icd_code) AS num_procedures
  FROM distinct_procedures
  GROUP BY subject_id
)
SELECT 
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] - 
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS iqr
FROM procedure_counts;