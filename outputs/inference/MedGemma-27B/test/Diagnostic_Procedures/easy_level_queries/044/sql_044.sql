WITH PatientCohort AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 56 AND 66
),
RelevantProcedures AS (
  SELECT
    itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    label LIKE '%mechanical circulatory support%'
),
PatientProcedures AS (
  SELECT
    pe.subject_id,
    pe.itemid
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
  INNER JOIN PatientCohort AS pc
    ON pe.subject_id = pc.subject_id
  INNER JOIN RelevantProcedures AS rp
    ON pe.itemid = rp.itemid
)
SELECT
  STDDEV(num_distinct_procedures)
FROM (
  SELECT
    subject_id,
    COUNT(DISTINCT itemid) AS num_distinct_procedures
  FROM PatientProcedures
  GROUP BY
    subject_id
) AS ProcedureCounts;