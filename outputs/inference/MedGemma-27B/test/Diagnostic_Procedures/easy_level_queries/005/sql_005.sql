WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
),
ProcedureCounts AS (
  SELECT
    pe.subject_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
  WHERE
    pe.subject_id IN (SELECT subject_id FROM PatientCohort)
    AND pe.itemid IN (
      SELECT
        di.itemid
      FROM
        `physionet-data.mimiciv_3_1_icu.d_items` AS di
      WHERE
        di.label LIKE '%Echocardiography%'
    )
  GROUP BY
    pe.subject_id
)
SELECT
  APPROX_QUANTILES(distinct_procedure_count, 4)[OFFSET(3)] AS percentile_75
FROM
  ProcedureCounts;