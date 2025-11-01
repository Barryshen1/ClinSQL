WITH
-- Get echocardiography ICD codes
echo_icd_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%echocardiogram%'
),

-- Count distinct echocardiography procedures per patient
patient_procedure_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS echo_procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  JOIN echo_icd_codes echo
    ON proc.icd_code = echo.icd_code
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
  GROUP BY p.subject_id
)

-- Calculate the 75th percentile
SELECT
  APPROX_QUANTILES(echo_procedure_count, 100)[OFFSET(75)] AS percentile_75
FROM patient_procedure_counts;