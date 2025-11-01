WITH PatientProcedures AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON p.subject_id = proc.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age >= 78
    AND p.anchor_age <= 88
    AND proc.icd_code LIKE 'Z95%' -- ICD-10 codes for pacemakers and ICDs start with Z95
  GROUP BY
    p.subject_id
)
SELECT
  PERCENTILE_CONT(0.25, distinct_procedure_count) AS percentile_25
FROM PatientProcedures;