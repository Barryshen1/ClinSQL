WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 50
    AND p.anchor_year_group = '45-55'
),
ProcedureCounts AS (
  SELECT
    h.subject_id,
    COUNT(DISTINCT h.icd_code) AS distinct_procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS h
  WHERE
    h.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientCohort
    )
    AND h.icd_code LIKE '33%' -- Filter for CABG procedures (ICD-10 codes starting with 33)
  GROUP BY
    h.subject_id
)
SELECT
  APPROX_QUANTILES(distinct_procedure_count, 4)[OFFSET(1)] AS percentile_25
FROM
  ProcedureCounts;