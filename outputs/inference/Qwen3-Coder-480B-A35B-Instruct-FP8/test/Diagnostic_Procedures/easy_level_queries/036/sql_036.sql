WITH valve_procedures AS (
  SELECT
    p.subject_id,
    proc.icd_code
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd proc
  USING
    (subject_id)
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dproc
  ON
    proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND LOWER(dproc.long_title) LIKE '%valve%'
    AND (LOWER(dproc.long_title) LIKE '%repair%' OR LOWER(dproc.long_title) LIKE '%replacement%')
),
distinct_procedure_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_valve_procedures
  FROM
    valve_procedures
  GROUP BY
    subject_id
)
SELECT
  AVG(distinct_valve_procedures) AS avg_distinct_valve_procedures_per_patient
FROM
  distinct_procedure_counts;