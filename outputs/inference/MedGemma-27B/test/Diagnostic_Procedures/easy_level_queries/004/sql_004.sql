WITH PatientAgeGroup AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 41 AND 51
),
ProcedureCounts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_procedure_count
  FROM PatientAgeGroup AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
    ON p.subject_id = pr.subject_id
  WHERE
    pr.icd_code LIKE '33%' -- ICD-10 codes for CABG start with 33
  GROUP BY
    p.subject_id
)
SELECT
  STDDEV(distinct_procedure_count) AS std_dev_distinct_cabg_procedures
FROM ProcedureCounts;