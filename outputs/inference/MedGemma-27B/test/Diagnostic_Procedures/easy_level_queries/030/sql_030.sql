WITH PatientAgeGroup AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 84 AND 94
),
ProcedureCounts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_procedure_count
  FROM PatientAgeGroup AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON p.subject_id = proc.subject_id
  WHERE
    proc.icd_code LIKE '33%' -- ICD-10 codes for Echocardiography start with 33
  GROUP BY
    p.subject_id
)
SELECT
  PERCENTILE_CONT(0.25, distinct_procedure_count) AS percentile_25
FROM ProcedureCounts;