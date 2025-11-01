WITH PatientAgeGroup AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 82 AND 92
),
ProcedureCounts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_procedure_count
  FROM PatientAgeGroup AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON a.hadm_id = proc.hadm_id
  GROUP BY
    p.subject_id
)
SELECT
  PERCENTILE_CONT(0.25, distinct_procedure_count) AS percentile_25
FROM ProcedureCounts;