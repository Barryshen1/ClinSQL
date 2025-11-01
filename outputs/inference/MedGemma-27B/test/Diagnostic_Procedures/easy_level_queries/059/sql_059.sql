WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 76 AND 86
),
ProcedureCounts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_procedure_count
  FROM
    PatientAge AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
      ON p.subject_id = pr.subject_id
  GROUP BY
    p.subject_id
)
SELECT
  PERCENTILE_CONT(0.25, distinct_procedure_count) AS IQR_Q1,
  PERCENTILE_CONT(0.75, distinct_procedure_count) AS IQR_Q2
FROM
  ProcedureCounts;