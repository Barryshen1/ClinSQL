WITH RelevantPatients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age = 45
),
RelevantProcedures AS (
  SELECT
    p.subject_id,
    pr.icd_code
  FROM
    RelevantPatients AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
    ON p.subject_id = pr.subject_id
  WHERE
    pr.icd_code LIKE '39%' -- ICD-10 codes for mechanical circulatory support start with 39
),
ProcedureCounts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_procedure_count
  FROM
    RelevantProcedures
  GROUP BY
    subject_id
)
SELECT
  MIN(distinct_procedure_count) AS min_distinct_procedures
FROM
  ProcedureCounts;