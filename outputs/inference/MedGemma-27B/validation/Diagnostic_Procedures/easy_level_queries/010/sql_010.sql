WITH EchocardiographyProcedures AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON pr.subject_id = p.subject_id
  WHERE
    pr.icd_code LIKE '93%' -- ICD-9 codes for echocardiography start with 93
    AND p.gender = 'M'
    AND p.anchor_age >= 84
    AND p.anchor_age <= 94
)
SELECT
  MAX(num_procedures) AS max_distinct_procedures
FROM (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS num_procedures
  FROM EchocardiographyProcedures
  GROUP BY
    subject_id
) AS procedure_counts;