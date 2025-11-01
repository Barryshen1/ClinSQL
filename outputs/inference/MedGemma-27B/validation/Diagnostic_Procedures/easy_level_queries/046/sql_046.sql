WITH PatientAgeGroup AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 80 AND 90
),
ProcedureCounts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_procedure_count
  FROM PatientAgeGroup AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON p.subject_id = proc.subject_id
  WHERE
    proc.icd_code LIKE '39%' -- ICD-9 codes for mechanical circulatory support
    OR proc.icd_code LIKE '996%' -- ICD-10 codes for mechanical circulatory support
  GROUP BY
    p.subject_id
)
SELECT
  MAX(distinct_procedure_count) AS max_distinct_procedures
FROM ProcedureCounts;