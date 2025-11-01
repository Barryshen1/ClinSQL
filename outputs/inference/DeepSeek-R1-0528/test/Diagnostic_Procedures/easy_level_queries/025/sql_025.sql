WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),
mcs_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    LOWER(long_title) LIKE '%intra-aortic balloon%' OR
    LOWER(long_title) LIKE '%balloon pump%' OR
    LOWER(long_title) LIKE '%extracorporeal membrane oxygenation%' OR
    LOWER(long_title) LIKE '%ecmo%' OR
    LOWER(long_title) LIKE '%ventricular assist%' OR
    LOWER(long_title) LIKE '%vad%'
),
patient_procedures AS (
  SELECT
    c.subject_id,
    -- Create unique identifier for each procedure type (code + version)
    CONCAT(p.icd_code, '_', p.icd_version) AS procedure_id
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.subject_id = p.subject_id
  LEFT JOIN mcs_codes m
    ON p.icd_code = m.icd_code
    AND p.icd_version = m.icd_version
  -- Only count rows with valid MCS procedures (non-MCS procedures become NULL)
  WHERE m.icd_code IS NOT NULL
),
distinct_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT procedure_id) AS num_distinct_procedures
  FROM patient_procedures
  GROUP BY subject_id
)
SELECT
  MIN(num_distinct_procedures) AS min_num_distinct_procedures
FROM distinct_counts;