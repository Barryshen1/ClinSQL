WITH AgeGroupProcedureCounts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
      ON p.subject_id = proc.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 86 AND 96
  GROUP BY
    p.subject_id
)
SELECT
  PERCENTILE_CONT(0.25, ARRAY_AGG(distinct_procedure_count)) AS iqr_lower,
  PERCENTILE_CONT(0.75, ARRAY_AGG(distinct_procedure_count)) AS iqr_upper
FROM
  AgeGroupProcedureCounts;