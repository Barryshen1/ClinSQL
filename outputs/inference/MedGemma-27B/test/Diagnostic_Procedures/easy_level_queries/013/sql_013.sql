WITH PatientAge AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 57 AND 67
), ProcedureCounts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_procedure_count
  FROM PatientAge AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON p.subject_id = proc.subject_id
  WHERE
    proc.icd_code LIKE '33%' -- ICD-10 codes for valve repair/replacement start with 33
  GROUP BY
    p.subject_id
)
SELECT
  MIN(distinct_procedure_count) AS min_distinct_procedures
FROM ProcedureCounts;